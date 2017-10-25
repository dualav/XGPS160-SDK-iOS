//
//  XGPS160API.m
//  XGPS160 Developers Kit.
//
//  Version 1.5.2
//  Licensed under the terms of the BSD License, as specified below.
//  Modified by Mr.choi on 2017. 3. 30..

/*
 Changes since 1.5.1
 - Streams full NMEA sentence with prefix "$G"
 - Expans the resolution of lon/lat from 3bytes to 4bytes
 
 Changes since 1.3
 - Adjusted closeSession to first close session and then set the delegate to nil.
 - Adjusted NSStreamEventEndEncountered handler to not close the connection.
 - fixed why self.serialNumber was getting empty data
 - changed the streams to currentRunLoop from mainRunLoop
 - added write-to-file for debug purposes
 - added checks to confirm it was an XGPS150/160 on the connect and disconnect notification handlers
 - updated for 64-bit compatibility
 
 Changes since 1.2:
 - added CRC checking to incoming data
 - added additional data integrity checks to the PRMC message parsing
 
 Changes since 1.1:
 - added additional data integrity checks to the parseNMEA method
 */

/*
 Copyright (c) 2017 Dual Electronics Corp.
 All rights reserved.
 
 Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
 
 Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
 Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
 Neither the name of the Dual Electronics Corporation nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "XGPS160API.h"

#import <ExternalAccessory/ExternalAccessory.h>

#define kProcessTimerDelay		0.6     // See note in the processConnectNotifications method for explanation of this.
#define kBufferSize             1024
#define kVolt415				644     // Battery level conversion constant.
#define kVolt350				543     // Battery level conversion constant.
#define kMaxNumberOfSatellites  16      // Max number of visible satellites in each system
#define kLatLonBitResolution       2.1457672e-5
#define kTrackHeadingResolution         1.40625
#define kSleepTimeBetweenCommandRetries 0.3
#define kCalcAvgSNRUsingGPS             YES
#define kCalcAvgSNRUsingGLONASS         NO
#define kLogListItemProcessingDelayTime 0.2
#define kReadDeviceSettingAfterDelay    0.5

// Set these to YES to see the NMEA sentence data logged to the debugger console
#define DEBUG_SENTENCE_PARSING  NO
#define DEBUG_CRC_CHECK         NO
#define DEBUG_DEVICE_DATA       NO
#define DEBUG_PGGA_INFO         NO
#define DEBUG_PGSA_INFO         NO
#define DEBUG_NGSA_INFO         NO
#define DEBUG_PGSV_INFO         NO
#define DEBUG_LGSV_INFO         NO
#define DEBUG_PVTG_INFO         NO
#define DEBUG_PRMC_INFO         NO
#define DEBUG_PGLL_INFO         NO

@interface XGPS160API()

@property BOOL logListItemTimerStarted;
@property BOOL newLogListItemReceived;
@property (nonatomic, strong) NSTimer *logListItemTimer;

@property bool notificationType;
@property (strong, nonatomic) NSNotification *mostRecentNotification;
@property (strong, nonatomic) EAAccessory *accessory;
@property NSUInteger accessoryConnectionID;
@property (strong, nonatomic) EASession   *session;
@property (strong, nonatomic) NSString *protocolString;

@end

@implementation XGPS160API

static unsigned int		rxIdx = 0;
static bool		rxSync = 0;
static bool		rxBinSync;
static unsigned int		rxBinLen;

volatile int	rsp160_cmd;
volatile unsigned char  rsp160_buf[256];
volatile unsigned int   rsp160_len;

UINT	rxBytesCount;
UINT	rxBytesTotal;
UINT	rxMessagesTotal;

BYTE	pktBuf[4096];

BYTE	cfgGpsSettings;
BYTE	cfgLogInterval;
USHORT	cfgLogBlock;
USHORT	cfgLogOffset;

UINT	tLogListCommand;

logentry_t      logRecords[185 * 510];      // 185 records per block, 510 blocks total
unsigned long   logReadBulkCount;
unsigned long   logBulkRecodeCnt;
unsigned long   logBulkByteCnt;

bool queueTimerStarted = NO;

unsigned short  indexOfLastValidGPSSampleInLog;
unsigned short  totalGPSSamplesInLogEntry;




#pragma mark - BT Stream Data Processing Methods
- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode
{
    switch(eventCode)
    {
        case NSStreamEventEndEncountered:
        {
            //NSLog(@"%s. NSStreamEventEndEncountered\n", __FUNCTION__);
            break;
        }
        case NSStreamEventHasBytesAvailable:
        {
            NSInteger		len = 0;
            uint8_t         buffer[kBufferSize];
            
            // read ADSB stream
            len = [[self.session inputStream] read:buffer maxLength:(kBufferSize-1)];
            
            if (len == 0)
            {
                //NSLog(@"%s. Received 0 bytes.", __FUNCTION__);
                break;
            }
            
            buffer[len] = '\0';
            [self logReceiveByte:(const unsigned char* )buffer len:(int)len];
            
            break;
        }
            
        case NSStreamEventHasSpaceAvailable:
        {
            //NSLog(@"%s. NSStreamEventHasSpaceAvailable\n", __FUNCTION__);
            break;
        }
            
        case NSStreamEventErrorOccurred:
        {
            //NSLog(@"%s. NSStreamEventErrorOccurred\n", __FUNCTION__);
            break;
        }
        case NSStreamEventNone:
        {
            //NSLog(@"%s. NSStreamEventNone\n", __FUNCTION__);
            break;
        }
        case NSStreamEventOpenCompleted:
        {
            //NSLog(@"%s. NSStreamEventOpenCompleted\n", __FUNCTION__);
            break;
        }
        default:
        {
            //NSLog(@"%s. Some other stream event occurred.\n", __FUNCTION__);
            break;
        }
    }
}

- (void)printBytes:(unsigned char *)c length:(int)l
{
    printf("Received bytes: ");
    for (int i=0; i<l; i++) printf("0x%.2X ",c[i]);
    printf("\n");
}

-(void) logReceiveByte :(const unsigned char*)pLine len:(int)len
{
    int         i;
    uint8_t     x;
    
    rxBytesCount += len;
    
    for (i=0; i<len; i++)
    {
        
        x = pLine[i];
        
        if (rxBinSync)
        {
            pktBuf[rxIdx] = x;
            rxIdx++;
            switch (rxIdx)
            {
                case 2:	// second marker
                    if (x != 0xEE) rxBinSync = FALSE;
                    break;
                    
                case 3:	// length
                    rxBinLen = x;
                    break;
            }
            
            if (rxIdx == (rxBinLen + 4))
            {
                [self parseCommandResponsesFromXGPS];
                rxBinSync = FALSE;
            }
            
            continue;
        }
        
        if (x == 0x88)
        {
            rxBinSync = TRUE;
            rxBinLen = 0;
            rxIdx = 1;
            pktBuf[0] = x;
            continue;
        }
        
        if (!rxSync)
        {
            if (x == 'P' || x == 'N' || x == 'L' || x == '@')
            {
                rxSync = 1;
                rxIdx = 0;
                pktBuf[0] = x;
            }
        }
        else
        {
            rxIdx++;
            pktBuf[rxIdx] = x;
            
            if (x == '\n')
            {
                rxMessagesTotal++;
                rxSync = 0;
                
                pktBuf[rxIdx+1] = 0;
                
                [self parseNMEA:(const char *)pktBuf length:(rxIdx + 1)];
            }
        }
    }
}

- (void)parseCommandResponsesFromXGPS
{
    BYTE	cs = 0;
    BYTE	i;
    BYTE	size;
    size = rxBinLen + 3;
    
    for( i=0; i<size; i++ ) {
        cs += pktBuf[i];
    }
    
    if( cs != pktBuf[rxBinLen + 3] )
    {
        //NSLog(@"%s. Checksum error. Skipping...", __FUNCTION__);
        return;
    }
    
    switch (pktBuf[3])
    {
        case cmd160_ack:
        case cmd160_nack:
            rsp160_cmd = pktBuf[3];
            rsp160_len = 0;
            break;
            
        case cmd160_fwRsp:
            rsp160_cmd = pktBuf[3];
            rsp160_buf[0] = pktBuf[4];
            rsp160_buf[1] = pktBuf[5];
            rsp160_buf[2] = pktBuf[6];
            rsp160_buf[3] = pktBuf[7];
            rsp160_len = rxBinLen;
            
            if (pktBuf[4] == cmd160_getSettings)
            {
                //NSLog(@"%s. XGPS160 sending settings.", __FUNCTION__);
                USHORT	blk;
                USHORT	offset;
                
                blk = pktBuf[8];
                blk <<= 8;
                blk |= pktBuf[7];
                
                offset = pktBuf[10];
                offset <<= 8;
                offset |= pktBuf[9];
                
                cfgGpsSettings = pktBuf[5];
                cfgLogInterval = pktBuf[6];
                self.logUpdateRate = pktBuf[6];
                //NSLog(@"%s. log update rate byte value is %d.", __FUNCTION__, self.logUpdateRate);
                
                cfgLogBlock = blk;
                cfgLogOffset = offset;
                
                if( cfgGpsSettings & 0x40 )
                {
                    //NSLog(@"Datalog Enabled\r\n");
                    self.alwaysRecordWhenDeviceIsOn = YES;
                }
                else
                {
                    //NSLog(@"Datalog Disabled\r\n");
                    self.alwaysRecordWhenDeviceIsOn = NO;
                }
                
                if( cfgGpsSettings & 0x80 )
                {
                    //NSLog(@"Datalog OverWrite\r\n");
                    self.stopRecordingWhenMemoryFull = NO;
                }
                else
                {
                    //NSLog(@"Datalog no OverWrite\r\n");
                    self.stopRecordingWhenMemoryFull = YES;
                }
                
                self.deviceSettingsHaveBeenRead = YES;
                NSNotification *status = [NSNotification notificationWithName:@"DeviceSettingsValueChanged" object:self];
                [[NSNotificationCenter defaultCenter] postNotification:status];
            }
            else if (pktBuf[4] == cmd160_logListItem)
            {
                NSMutableDictionary *logDic;
                
                USHORT          listIdx;
                USHORT          listTotal;
                loglistitem_t	li;
                loglistitem_t   *plistitem;
                
                listIdx = pktBuf[6];
                listIdx <<= 8;
                listIdx |= pktBuf[7];
                
                listTotal = pktBuf[8];
                listTotal <<= 8;
                listTotal |= pktBuf[9];
                
                plistitem = &li;
                
                // There is bug in firmware v. 1.3.0. The cmd160_logList command will append a duplicate of the last long
                // entry. For example, if there are 3 recorded logs, the command will repond that there are four: log 0,
                // log 1, log 2 and log 2 again.
                
                if (listIdx == listTotal)
                {
                    listIdx = 0;
                    listTotal = 0;
                    logDic = nil;
                }
                else
                {
                    memcpy ((void *)plistitem, &pktBuf[10], sizeof(loglistitem_t));
                    
                    logDic = nil;
                    logDic = [[NSMutableDictionary alloc] init];
                    
                    // Create the date & time objects
                    NSString *dateString = [NSString stringWithFormat:@"%s",dateStr(plistitem->startDate)];
                    NSString *timeString = [NSString stringWithFormat:@"%s",todStr(plistitem->startTod)];
                    
                    
                    
                    
                    
                    
                    
                    
                    //UTC time
                    NSDateFormatter *utcDateFormatter = [[NSDateFormatter alloc] init] ;
                    [utcDateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
                    [utcDateFormatter setTimeZone :[NSTimeZone timeZoneForSecondsFromGMT: 0]];
                    
                    // utc format
                    NSDate *dateInUTC = [utcDateFormatter dateFromString: [NSString stringWithFormat:@"%@ %@",dateString,timeString]];
                    
                    // offset second
                    NSInteger seconds = [[NSTimeZone systemTimeZone] secondsFromGMT];
                    
                    // format it and send
                    NSDateFormatter *localDateFormatter = [[NSDateFormatter alloc] init] ;
                    [localDateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
                    [localDateFormatter setTimeZone :[NSTimeZone timeZoneForSecondsFromGMT: seconds]];
                    
                    
                    // formatted string
                    NSString *str_localDate = [localDateFormatter stringFromDate: dateInUTC];
                    //               NSDate *DeviceDate = [utcDateFormatter dateFromString:str_localDate];
                    
                    
                    
                    [localDateFormatter setDateFormat:@"yyyy-MM-dd"];
                    NSString *str_date = [localDateFormatter stringFromDate:dateInUTC];
                    
                    
                    
                    [localDateFormatter setDateFormat:@"HH:mm:ss"];
                    NSString *str_time = [localDateFormatter stringFromDate:dateInUTC];
                    [logDic setObject:str_date forKey:@"DeviceStartDate"];
                    [logDic setObject:str_time forKey:@"DeviceStartTime"];
                    [logDic setObject:[NSString stringWithFormat:@"%@ %@",str_date,str_time] forKey:@"DevicerecordingStart"];
                    
                    
                    
                    
                    
                    
                    
                    
                    
                    [logDic setObject:dateString forKey:@"humanFriendlyStartDate"];
                    [logDic setObject:[self prettyTime:(plistitem->startTod)] forKey:@"humanFriendlyStartTime"];
                    [logDic setObject:[self dateFromTime:timeString andDate:dateString] forKey:@"recordingStart"];
                    
                    // Create the duration objects
                    [logDic setObject: [NSNumber numberWithUnsignedChar:plistitem->interval] forKey:@"interval"];
                    [logDic setObject: [NSNumber numberWithUnsignedShort:plistitem->countEntry] forKey:@"countEntry"];
                    
                    float sampleInterval = (float)plistitem->interval;
                    if (plistitem->interval == 255) sampleInterval = 10.0;
                    
                    float recordingLengthInSecs = (float)plistitem->countEntry * sampleInterval / 10.0;
                    unsigned durationHrs, durationMins, durationSecs;
                    durationHrs = floor(recordingLengthInSecs / 3600);
                    durationMins = floor((recordingLengthInSecs - (durationHrs * 3600)) / 60.0);
                    durationSecs = recordingLengthInSecs - (durationHrs * 3600) - (durationMins * 60);
                    
                    if (durationHrs > 0)
                        [logDic setObject:[NSString stringWithFormat:@"%02d:%02d:%02d", durationHrs, durationMins, durationSecs] forKey:@"humanFriendlyDuration"];
                    else if (durationMins > 0)
                        [logDic setObject:[NSString stringWithFormat:@"00:%02d:%02d", durationMins, durationSecs] forKey:@"humanFriendlyDuration"];
                    else
                        [logDic setObject:[NSString stringWithFormat:@"00:00:%02d", durationSecs] forKey:@"humanFriendlyDuration"];
                    
                    
                    // Add the remaining elements
                    [logDic setObject: [NSString stringWithFormat:@"%s",todStr(plistitem->sig)] forKey:@"sig"];
                    [logDic setObject: [NSNumber numberWithUnsignedShort:plistitem->startDate] forKey:@"startDate"];
                    [logDic setObject: [NSNumber numberWithUnsignedInt:plistitem->startTod] forKey:@"startTod"];
                    [logDic setObject: [NSNumber numberWithUnsignedShort:plistitem->startBlock] forKey:@"startBlock"];
                    [logDic setObject: [NSNumber numberWithUnsignedShort:plistitem->countBlock] forKey:@"countBlock"];
                    
                    [self.arr_logListEntries addObject:logDic];
                    
                    logDic = nil;
                    self.newLogListItemReceived = YES;
                    [self processLogListEntriesAfterDelay];
                }
            }
            else if (pktBuf[4] == cmd160_logReadBulk)
            {
                UINT	addr;
                BYTE	dataSize;
                
                addr = pktBuf[6];
                addr <<= 8;
                addr |= pktBuf[7];
                addr <<= 8;
                addr |= pktBuf[8];
                
                dataSize = pktBuf[9];
                
                logReadBulkCount += (dataSize / sizeof(logentry_t));
                
                if (addr == 0 && dataSize == 0)
                {
                    // End-of-data
                    logReadBulkCount |= 0x1000000;
                    
                    [self decodeLogBulk];
                    
                    logReadBulkCount = 0;
                    logBulkRecodeCnt = 0;
                    logBulkByteCnt = 0;
                    memset(logRecords, 0, 185 * 510);
                }
                else
                {
                    BYTE *p = &pktBuf[10];
                    
                    for (i=0; i<5; i++)
                    {
                        memcpy (&logRecords[logBulkRecodeCnt + i], p, sizeof(logentry_t));
                        p += sizeof(logentry_t);
                    }
                    
                    logBulkRecodeCnt += 5;
                    logBulkByteCnt = logBulkRecodeCnt;
                }
            }
            else if (pktBuf[4] == cmd160_logDelBlock)
            {
                
                //if (pktBuf[5] == 0x01) [self getListOfRecordedLogs];
                //else NSLog(@"Error deleting block data.");
                
                if (pktBuf[5] != 0x01) NSLog(@"Error deleting block data.");
                
            }
            break;
            
        case cmd160_response:
            rsp160_cmd = pktBuf[3];
            rsp160_len = 0;
            break;
            
        default:
            break;
    }
}

- (int) getUsedStoragePercent
{
    int percent;
    int countBlock=0;
    
    for (NSDictionary*dic in _arr_logListEntries) {
        countBlock += [[dic objectForKey:@"countBlock"]integerValue];
    }
    
    percent = (countBlock * 1000 / 520);
    if( percent > 0 && percent < 10) {
        percent = 10;
    }
    
    return percent / 10;
}


//======================================================================================
// LOG DATA DECODE
//======================================================================================

static double getLatLon24bit( BYTE* buf )
{
#define kLatLonBitResolution       2.1457672e-5
    
    double  d;
    int r;
    
    r = buf[0];
    r <<= 8;
    r |= buf[1];
    r <<= 8;
    r |= buf[2];
    
    d = ((double)r) * kLatLonBitResolution;
    
    if( r & 0x800000 ) {	// is South / West ?
        d = -d;
    }
    
    return d;
}

static unsigned int getUInt24bit( BYTE* buf )
{
    unsigned int r;
    
    r = buf[0];
    r <<= 8;
    r |= buf[1];
    r <<= 8;
    r |= buf[2];
    
    return r;
}

static double getLatLon32bit( BYTE* buf )
{
    double  d;
    int r;
    
    r = buf[0];
    r <<= 8;
    r |= buf[1];
    r <<= 8;
    r |= buf[2];
    r <<= 8;
    r |= buf[3];
    
    d = ((double)r) * 0.000001;
    
    return d;
}

- (void)decodeLogBulk
{
    logentry_t*		e;
    UINT			tod;
    UINT			tod10th;
    UINT            spd;
    USHORT          dateS;
    double			fLat=0;
    double			fLon=0;
    double          fAlt=0;
    double          fHeading=0;
    
    [self.arr_logDataSamples removeAllObjects];
    
    for (unsigned long i=0; i<logBulkRecodeCnt; i++)
    {
        e = &logRecords[i];
        
        if( e->type == 0 )// type=0 Original XGPS160 24-bit lat/lon (pre-v2.4/v3.4)
        {
            dataentry_t*    d = &e->data;
            
            tod = (d->tod2 & 0x10);
            tod <<= 12;
            tod |= d->tod;
            tod10th = d->tod2 & 0x0F;
            
            fLat = getLatLon24bit( d->lat );
            fLon = getLatLon24bit( d->lon );
            //fAlt = getUInt24bit( d->alt ) * 5.0 / 3.2808399;// 5feet unit -> meters
            fAlt = getUInt24bit( d->alt ) * 5.0;// 5feet unit -> 1feet unit
            
            spd = d->spd[0];
            spd <<= 8;
            spd |= d->spd[1];
            
            fHeading = (double)d->heading * 360.0 / 256.0;
            
            dateS = d->date;
        }
        else if( e->type == 2 )// type=2 New 32-bit lat/lon
        {
            data2entry_t*    d = &e->data2;
            
            tod = (d->tod2 & 0x10);
            tod <<= 12;
            tod |= d->tod;
            tod10th = d->tod2 & 0x0F;
            
            fLat = getLatLon32bit( d->lat );
            fLon = getLatLon32bit( d->lon );
            // altitude in data2entry_t is in centimeter unit
            //fAlt = ((double)getUInt24bit( d->alt )) / 100.0;// cm(centi-meter) unit -> meters
            fAlt = ((double)getUInt24bit( d->alt )) / 100.0 / 0.3048;// cm(centi-meter) unit -> feet
            
            spd = d->spd[0];
            spd <<= 8;
            spd |= d->spd[1];
            
            fHeading = (double)d->heading * 360.0 / 256.0;
            
            dateS = d->date;
        }
        else
        {
            break;
        }
        //UTC time
        NSDateFormatter *utcDateFormatter = [[NSDateFormatter alloc] init] ;
        [utcDateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss.SS"];
        [utcDateFormatter setTimeZone :[NSTimeZone timeZoneForSecondsFromGMT: 0]];
        
        // utc format
        NSDate *dateInUTC = [utcDateFormatter dateFromString: [NSString stringWithFormat:@"%@ %@",[NSString stringWithFormat:@"%s",dateStr(dateS)],[NSString stringWithFormat:@"%s",tod2Str(tod, tod10th)]]];
        
        // offset second
        NSInteger seconds = [[NSTimeZone systemTimeZone] secondsFromGMT];
        
        // format it and send
        NSDateFormatter *localDateFormatter = [[NSDateFormatter alloc] init] ;
        [localDateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss.SS"];
        [localDateFormatter setTimeZone :[NSTimeZone timeZoneForSecondsFromGMT: seconds]];
        
        
        // formatted string
        NSString *str_localDate = [localDateFormatter stringFromDate: dateInUTC];
        NSDate *DeviceDate = [utcDateFormatter dateFromString:str_localDate];
        
        
        [localDateFormatter setDateFormat:@"yyyy-MM-dd"];
        NSString *str_date = [localDateFormatter stringFromDate:dateInUTC];
        [localDateFormatter setTimeZone :[NSTimeZone timeZoneForSecondsFromGMT: seconds]];
        
        [localDateFormatter setDateFormat:@"HH:mm:ss.S"];
        NSString *str_timeinMilesec = [localDateFormatter stringFromDate:dateInUTC];
        [localDateFormatter setDateFormat:@"HH:mm:ss"];
        NSString *str_time = [localDateFormatter stringFromDate:dateInUTC];
        
        //
        //
        //        NSLog(@"DDate %@ DTime %@",str_date,str_time);
        //
        //        NSLog(@"utc date%@   utctime%@",[NSString stringWithFormat:@"%s",dateStr(le->data.date)],[NSString stringWithFormat:@"%s",tod2Str(tod, tod10th)]);
        //        NSLog(@"device Date %@",DeviceDate);
        
        
        
        NSMutableDictionary *bulkDic = [[NSMutableDictionary alloc] init];
        
        
        [bulkDic setObject:str_date forKey:@"Devicedate"];
        [bulkDic setObject:str_time forKey:@"Devicetime"];
        [bulkDic setObject:str_timeinMilesec forKey:@"DeviceTimeInMiliseconds"];
        
        
        [bulkDic setObject:[NSString stringWithFormat:@"%s",dateStr(dateS)] forKey:@"date"];
        [bulkDic setObject:[NSNumber numberWithDouble:fLat] forKey:@"lat"];
        [bulkDic setObject:[NSNumber numberWithDouble:fLon] forKey:@"lon"];
        [bulkDic setObject:[NSNumber numberWithDouble:fAlt] forKey:@"alt"];
        [bulkDic setObject:[NSString stringWithFormat:@"%s",todTimeOnly(tod)] forKey:@"time"];
        [bulkDic setObject:[NSString stringWithFormat:@"%s",tod2Str(tod, tod10th)] forKey:@"utc"];
        [bulkDic setObject:[NSNumber numberWithUnsignedInt:spd] forKey:@"speed"];
        [bulkDic setObject:[NSNumber numberWithDouble:fHeading] forKey:@"heading"];
        [bulkDic setObject:[NSString stringWithFormat:@"%s %s",dateStr(dateS), tod2Str(tod, tod10th)] forKey:@"titleText"];
        
        [self.arr_logDataSamples addObject:bulkDic];
    }
    
    // The device returns all data samples in the block and this will usually extend beyond the end of the valid data.
    // So truncate the returned array of data at the end of the actual data.
    [self.arr_logDataSamples removeObjectsInRange:NSMakeRange(totalGPSSamplesInLogEntry, [self.arr_logDataSamples count] - totalGPSSamplesInLogEntry)];
    
    NSNotification *status = [NSNotification notificationWithName:@"DoneReadingGPSSampleData" object:self];
    [[NSNotificationCenter defaultCenter] postNotification:status];
}


- (bool)sendCommandToDevice:(BYTE)cmd payloadDataArray:(unsigned char *)buf lengthOfPayloadDataArray:(unsigned int)bufLen
{
    static	BYTE	xbuf[256];
    UINT	size = 0;
    UINT	i;
    BYTE	cs;
    
    xbuf[0] = 0x88;
    xbuf[1] = 0xEE;
    xbuf[2] = bufLen + 1;	// length
    xbuf[3] = (BYTE) cmd;
    
    if( bufLen > 0 ) {
        if( buf == NULL ) {
            return FALSE;
        }
        if( bufLen > 248 ) {
            return FALSE;
        }
        memcpy( &xbuf[4], buf, bufLen );
    }
    
    size = 4 + bufLen;
    
    cs = 0;
    for( i=0; i<size; i++ ) {
        cs += xbuf[i];
    }
    
    xbuf[size] = cs;
    size++;
    
    NSInteger written = 0;
    char maxRetries = 5;
    
    do {
        if (self.session && [self.session outputStream])
        {
            if ([[self.session outputStream] hasSpaceAvailable])
            {
                written = [[self.session outputStream] write: xbuf maxLength:size];
            }
        }
        
        [NSThread sleepForTimeInterval:kSleepTimeBetweenCommandRetries];
        maxRetries--;
        
    } while (written == 0 || maxRetries == 0);
    
    if (written > 0) return TRUE;
    else
    {
        //NSLog(@"%s. Nothing written to device.", __FUNCTION__);
        return FALSE;
    }
}

- (void)notifyUIOfNewLogListData
{
    if (self.newLogListItemReceived == YES)
    {
        self.newLogListItemReceived = NO;
    }
    else
    {
        // stop the timer
        if (self.logListItemTimer != nil)
        {
            if ([self.logListItemTimer isValid])
            {
                [self.logListItemTimer invalidate];
                self.logListItemTimer = nil;
            }
        }
        self.logListItemTimerStarted = NO;
        
        // sort the log list entry array going first to last
        NSSortDescriptor *valueDescriptor = [[NSSortDescriptor alloc] initWithKey:@"recordingStart" ascending:YES];
        NSArray *descriptors = [NSArray arrayWithObject:valueDescriptor];
        self.arr_logListEntries = [NSMutableArray arrayWithArray:[self.arr_logListEntries sortedArrayUsingDescriptors:descriptors]];
        
        // notify any view controllers that the log list creation is complete
        NSNotification *status = [NSNotification notificationWithName:@"DoneReadingLogListEntries" object:self];
        [[NSNotificationCenter defaultCenter] postNotification:status];
    }
}

- (void)processLogListEntriesAfterDelay
{
    /* In firmware versions earlier than 1.3.5, the device doesn't reliably send the total number of log entries
     stored in memory. So there is no way to know when transfer of the log entry list is finished, other than
     to use a timer.
     
     So what happens here is the utilization of a timer to defer processing until a few moments after the last
     log_entry_item message is received.
     
     A repeating timer is started. When the timer ends, there is a check whether new data has arrived. If so, the
     timer is allowed to repeat. If no new data has been received, the timer is cancelled and the received data
     is processed.
     */
    
    if (self.logListItemTimerStarted == NO)
    {
        //create timer
        self.logListItemTimer = [NSTimer timerWithTimeInterval:(kLogListItemProcessingDelayTime)
                                                        target:self
                                                      selector:@selector(notifyUIOfNewLogListData)
                                                      userInfo:nil
                                                       repeats:YES];
        
        [[NSRunLoop currentRunLoop] addTimer:self.logListItemTimer forMode:NSDefaultRunLoopMode];
        self.logListItemTimerStarted = YES;
    }
    else return;
}

#pragma mark - Utility methods
char *dateStr(USHORT ddd)
{
    static char str[20];
    
    
    int tmp;
    int yy, mm, dd;
    
    tmp = ddd;
    yy = 2012 + tmp/372;
    mm = 1 + (tmp % 372) / 31;
    dd = 1 + tmp % 31;
    
    //sprintf(str, "%04d/%02d/%02d", yy, mm, dd);  // e.g. 2014/06/14
    sprintf(str, "%04d-%02d-%02d", yy,mm, dd);    // e.g. 06/14/2014
    
    return str;
}

char *todStr(UINT tod)  // Returns time with whole seconds: HH:MM:SS
{
    static char str[20];
    int	hr, mn, ss;
    
    hr = tod / 3600;
    mn = (tod % 3600) / 60;
    ss = tod % 60;
    
    sprintf(str, "%02d:%02d:%02d", hr, mn, ss);
    
    return str;
}

char *tod2Str(USHORT tod, BYTE tod2)  // Returns time to the hundredth of a sec: HH:MM:SS.ss
{
    static char str[20];
    int	hr, mn, ss, tenths;
    
    hr = tod / 3600;
    mn = (tod % 3600) / 60;
    ss = tod % 60;
    tenths = tod2 & 0x0F;
    
    sprintf(str, "%02d:%02d:%02d.%01d", hr, mn, ss, tenths);
    
    return str;
}


char *todTimeOnly(USHORT tod)  // Returns time to the hundredth of a sec: HH:MM:SS.ss
{
    static char str[20];
    int	hr, mn, ss;
    
    hr = tod / 3600;
    mn = (tod % 3600) / 60;
    ss = tod % 60;
    sprintf(str, "%02d:%02d:%02d", hr, mn, ss);
    
    return str;
}


- (NSDate *)dateFromTime:(NSString *)timeString andDate:(NSString *)dateString
{
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    [df setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
    [df setTimeZone:[NSTimeZone localTimeZone]];
    [df setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
    
    NSString *combined = [NSString stringWithFormat:@"%@ %@", dateString, timeString];
    
    
    
    
    
    
    
    /*
     
     NSDateFormatter *utcDateFormatter = [[NSDateFormatter alloc] init] ;
     [utcDateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
     [utcDateFormatter setTimeZone :[NSTimeZone timeZoneForSecondsFromGMT: 0]];
     
     // utc format
     NSDate *dateInUTC = [utcDateFormatter dateFromString: combined];
     
     // offset second
     NSInteger seconds = [[NSTimeZone systemTimeZone] secondsFromGMT];
     
     // format it and send
     NSDateFormatter *localDateFormatter = [[NSDateFormatter alloc] init] ;
     [localDateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
     [localDateFormatter setTimeZone :[NSTimeZone timeZoneForSecondsFromGMT: seconds]];
     
     
     // formatted string
     NSString *str_localDate = [localDateFormatter stringFromDate: dateInUTC];
     NSDate *date_final = [localDateFormatter dateFromString:str_localDate];
     
     NSLog(@"%@",dateInUTC);
     
     */
    
    
    
    
    return [df dateFromString:combined];
}

- (NSString *)prettyTime:(UINT)tod
{
    int	hr, mn;
    
    hr = tod / 3600;
    if (hr == 0) hr = 12;
    
    mn = (tod % 3600) / 60;
    
    if (hr > 12) return [NSString stringWithFormat:@"%2d:%02d PM", (hr-12), mn];
    else return [NSString stringWithFormat:@"%2d:%02d AM", hr, mn];
}

- (float)calculateAvgUsableSatSNRWithSatSystem:(bool)GPSorGLONASS
{
    NSMutableArray *satData;
    int sumSatStrength=0;
    float avgSNR=0.0;
    
    NSNumber *numOfSatInUse;
    NSMutableDictionary *dictOfSatInfo;
    NSMutableArray *satsUsedInPosCalc;
    
    if (GPSorGLONASS == kCalcAvgSNRUsingGPS)
    {
        numOfSatInUse = self.numOfGPSSatInUse;
        dictOfSatInfo = self.dictOfGPSSatInfo;
        satsUsedInPosCalc = self.gpsSatsUsedInPosCalc;
    }
    else
    {
        numOfSatInUse = self.numOfGLONASSSatInUse;
        dictOfSatInfo = self.dictOfGLONASSSatInfo;
        satsUsedInPosCalc = self.glonassSatsUsedInPosCalc;
    }
    
    if (numOfSatInUse == 0) return 0.0f;	// error prevention
    
    for (NSNumber *sat in [dictOfSatInfo allKeys])
    {
        for (NSNumber *satInUse in satsUsedInPosCalc)
        {
            if ([sat intValue] == [satInUse intValue])
            {
                satData = [dictOfSatInfo objectForKey:sat];
                sumSatStrength += [[satData objectAtIndex:2] intValue];
            }
        }
    }
    
    avgSNR = (float)sumSatStrength / [numOfSatInUse floatValue];
    
    if (isnan(avgSNR) != 0) avgSNR = 0.0;   // check: making sure all SNR values are valid
    
    return avgSNR;
}

#pragma mark - Log Control Methods
- (void)startLoggingNow
{
    [self sendCommandToDevice:cmd160_logEnable payloadDataArray:nil lengthOfPayloadDataArray:0];
}

- (void)stopLoggingNow
{
    [self sendCommandToDevice:cmd160_logDisable payloadDataArray:nil lengthOfPayloadDataArray:0];
}

#pragma mark - Log Access and Management
- (void)getListOfRecordedLogs
{
    [self.arr_logListEntries removeAllObjects];
    
    [self sendCommandToDevice:cmd160_logList payloadDataArray:0 lengthOfPayloadDataArray:0];
}

- (void)getGPSSampleDataForLogListItem:(NSDictionary *)logListItem
{
    if (logListItem == nil) return;
    else
    {
        [self.arr_logDataSamples removeAllObjects];
        
        totalGPSSamplesInLogEntry = [[logListItem objectForKey:@"countEntry"] unsignedShortValue];
        unsigned short startBlock = [[logListItem objectForKey:@"startBlock"] unsignedShortValue];
        unsigned short countBlock = [[logListItem objectForKey:@"countBlock"] unsignedShortValue];
        
        uint8_t startBlockHigh = (startBlock & 0xFF00) >> 8;
        uint8_t startBlockLow = startBlock & 0x00FF;
        uint8_t countBlockHigh = (countBlock & 0xFF00) >> 8;
        uint8_t countBlockLow = countBlock & 0x00FF;
        
        unsigned char payloadArray[4] = {startBlockHigh, startBlockLow, countBlockHigh, countBlockLow};
        [self sendCommandToDevice:cmd160_logReadBulk payloadDataArray:payloadArray lengthOfPayloadDataArray:sizeof(payloadArray)];
    }
}

- (void)deleteGPSSampleDataForLogListItem:(NSDictionary *)logListItem
{
    if (logListItem == nil) return;
    else
    {
        // Delete the recorded log from the XGPS160 memory
        unsigned short startBlock = [[logListItem objectForKey:@"startBlock"] unsignedShortValue];
        unsigned short countBlock = [[logListItem objectForKey:@"countBlock"] unsignedShortValue];
        
        uint8_t startBlockHigh = (startBlock & 0xFF00) >> 8;
        uint8_t startBlockLow = startBlock & 0x00FF;
        uint8_t countBlockHigh = (countBlock & 0xFF00) >> 8;
        uint8_t countBlockLow = countBlock & 0x00FF;
        
        unsigned char payloadArray[4] = {startBlockHigh, startBlockLow, countBlockHigh, countBlockLow};
        [self sendCommandToDevice:cmd160_logDelBlock payloadDataArray:payloadArray lengthOfPayloadDataArray:sizeof(payloadArray)];
        
        // Remove the log entry from the log list array
        [self.arr_logListEntries removeObject:logListItem];
    }
}

- (void)enterLogAccessMode
{
    /* It's much simpler to deal with log data information while the device is not streaming GPS data. So the
     recommended practice is to pause the NMEA stream output during the time that logs are being accessed
     and manipulated.
     
     However, the command to pause the output needs to be sent from a background thread in order to ensure there
     is space available for an output stream. Only this command needs to be on the background thread. Once
     the stream is paused, commands can be sent on the main thread.
     */
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0), ^{
        [self sendCommandToDevice:cmd160_streamStop payloadDataArray:0 lengthOfPayloadDataArray:0];
        
        self.streamingMode = NO;
        
        // get the list of log data
        [self getListOfRecordedLogs];
    });
    
}

- (void)exitLogAccessMode
{
    // Remember to tell the XGPS160 to resume sending NMEA data once you are finished with the log data.
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0), ^{
        [self sendCommandToDevice:cmd160_streamResume payloadDataArray:0 lengthOfPayloadDataArray:0];
        
        self.streamingMode = YES;
    });
}

# pragma mark - Device Settings Methods
- (void)setNewLogDataToOverwriteOldData:(bool)overwrite
{
    /* When in streaming mode, this command needs to be sent from a background thread in order to ensure there
     is space available for an output stream. If the stream is paused, commands can be sent on the main thread.
     */
    if (self.streamingMode)
    {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0), ^{
            if (overwrite) [self sendCommandToDevice:cmd160_logOWEnable payloadDataArray:nil lengthOfPayloadDataArray:0];
            else [self sendCommandToDevice:cmd160_logOWDisable payloadDataArray:nil lengthOfPayloadDataArray:0];
            
        });
    }
    else
    {
        if (overwrite) [self sendCommandToDevice:cmd160_logOWEnable payloadDataArray:nil lengthOfPayloadDataArray:0];
        else [self sendCommandToDevice:cmd160_logOWDisable payloadDataArray:nil lengthOfPayloadDataArray:0];
    }
}

- (void)setAlwaysRecord:(bool)record
{
    /* When in streaming mode, this command needs to be sent from a background thread in order to ensure there
     is space available for an output stream. If the stream is paused, commands can be sent on the main thread.
     */
    if (self.streamingMode)
    {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0), ^{
            if (record) [self sendCommandToDevice:cmd160_logEnable payloadDataArray:nil lengthOfPayloadDataArray:0];
            else [self sendCommandToDevice:cmd160_logDisable payloadDataArray:nil lengthOfPayloadDataArray:0];
            
        });
    }
    else
    {
        if (record) [self sendCommandToDevice:cmd160_logEnable payloadDataArray:nil lengthOfPayloadDataArray:0];
        else [self sendCommandToDevice:cmd160_logDisable payloadDataArray:nil lengthOfPayloadDataArray:0];
    }
}

-(BOOL)checkForAdjustableRateLogging
{
    // Devices with firmware 1.3.5 and above have a configurable logging rate.
    // Devices with firmware versions less than 1.3.5 below cannot accept the rate change commands.
    // So check the firmware version and report yes if 1.3.5 or above.
    
    NSArray *versionNumbers = [self.firmwareRev componentsSeparatedByString:@"."];
    int majorVersion = [[versionNumbers objectAtIndex:0] intValue];
    int minorVersion = [[versionNumbers objectAtIndex:1] intValue];
    int subVersion = [[versionNumbers objectAtIndex:2] intValue];
    
    if (majorVersion > 1) return YES;
    else if (minorVersion > 3) return YES;
    else if ((minorVersion == 3) && (subVersion >= 5)) return YES;
    else return NO;
}

- (bool)setLoggingUpdateRate:(unsigned char)rate
{
    if ([self checkForAdjustableRateLogging] == NO) {
        NSLog(@"Device firware version does not support adjustable logging rates. Firmware 1.3.5 or greater is required.");
        NSLog(@"Firware updates are available through the XGPS160 Status Tool app.");
        return NO;
    }
    
    /* rate can only be one of the following vales:
     value  ->      device update rate
     1               10 Hz
     2               5 Hz
     5               2 Hz
     10              1 Hz
     20              once every 2 seconds
     30              once every 3 seconds
     40              once every 4 seconds
     50              once every 5 seconds
     100             once every 10 seconds
     120             once every 12 seconds
     150             once every 15 seconds
     200             once every 20 seconds
     */
    
    if ((rate != 1) && (rate != 2) && (rate != 5) && (rate != 10) &&
        (rate != 20) && (rate != 30) && (rate != 40) && (rate != 50) &&
        (rate != 100) && (rate != 120) && (rate != 150) && (rate != 200))
    {
        NSLog(@"%s. Invaid rate: %d", __FUNCTION__, rate);
        return NO;
    }
    
    /* When in streaming mode, this command needs to be sent from a background thread in order to ensure there
     is space available for an output stream. If the stream is paused, commands can be sent on the main thread.
     */
    
    if (self.streamingMode)
    {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0), ^{
            unsigned char payloadArray[1] = {rate};
            NSLog(@"%s. Streaming mode. Requested logging rate: %d", __FUNCTION__, rate);
            [self sendCommandToDevice:cmd160_logInterval payloadDataArray:payloadArray lengthOfPayloadDataArray:sizeof(payloadArray)];
        });
    }
    else
    {
        NSLog(@"%s. log access mode. Requested logging rate: %d", __FUNCTION__, rate);
        unsigned char payloadArray[1] = {rate};
        [self sendCommandToDevice:cmd160_logInterval payloadDataArray:payloadArray lengthOfPayloadDataArray:sizeof(payloadArray)];
    }
    
    return YES;
}

- (void)readDeviceSettings
{
    /* When in streaming mode, this command needs to be sent from a background thread in order to ensure there
     is space available for an output stream. If the stream is paused, commands can be sent on the main thread.
     */
    
    if (self.streamingMode)
    {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0), ^{
            [self sendCommandToDevice:cmd160_getSettings payloadDataArray:0 lengthOfPayloadDataArray:0];
        });
    }
    else
    {
        [self sendCommandToDevice:cmd160_getSettings payloadDataArray:0 lengthOfPayloadDataArray:0];
    }
    
}

# pragma mark - Data Input and Processing Methods
- (void)parseNMEA:(const char *)pLine length:(NSUInteger)len
{
    
    NSArray *elementsInSentence;
    
    // Parse the NMEA data stream from the GPS chipset. Check out http://aprs.gids.nl/nmea/ for a good
    // explanation of the various NMEA sentences.
    
    if (DEBUG_SENTENCE_PARSING) NSLog(@"%s. buffer text: %s", __FUNCTION__, pLine);
    
    // Determine which kind of sentence it is
    if (strncmp((char *)pLine, "@", 1) == 0)
    {
        // Case 1: parse the device info
        int vbat;
        float bvolt, batLevel;
        
        vbat = (unsigned char)pLine[1];
        vbat <<= 8;
        vbat |= (unsigned char)pLine[2];
        if (vbat < kVolt350)
            vbat = kVolt350;
        if (vbat > kVolt415)
            vbat = kVolt415;
        
        bvolt = (float)vbat * 330.0f / 512.0f;
        batLevel = ((bvolt / 100.0f) - 3.5f) / 0.65f;
        
        if (batLevel > 1.0)
            self.batteryVoltage = 1.0;
        else if (batLevel < 0)
            self.batteryVoltage = 0.0;
        else
            self.batteryVoltage = batLevel;
        
        if( pLine[5] & 0x04 )
            self.isCharging = YES;
        else
            self.isCharging = NO;
        
        // Trigger a notification to the view controllers that a new device data sentence has been received.
        // This also signifies that a complete cycle of NMEA sentences have been sent.
        NSNotification *deviceDataUpdated = [NSNotification notificationWithName:@"DeviceDataUpdated" object:self];
        [[NSNotificationCenter defaultCenter] postNotification:deviceDataUpdated];
        
        return;
    }
    
    // At this point, the data in the buffer is determined to be NMEA sentence data.
    // We'll treat it as delimeted string data
    
    // Create a string from the raw buffer data
    NSString *sentence = [[NSString alloc] initWithUTF8String:pLine];
    if (DEBUG_SENTENCE_PARSING) NSLog(@"%s. sentence is: %@", __FUNCTION__, sentence);
    
    // Perform a CRC check. The checksum field consists of a "*" and two hex digits representing
    // the exclusive OR of all characters between, but not including, the "$" and "*".
    unichar digit=0, crcInString=0, calculatedCrc='G';
    NSUInteger i=0;
    
    while (i < [sentence length])
    {
        digit = [sentence characterAtIndex:i];
        if (digit == 42)    // found the asterisk
        {
            unichar firstCRCChar = [sentence characterAtIndex:(i+1)];
            unichar secondCRCChar = [sentence characterAtIndex:(i+2)];
            
            if (firstCRCChar > 64) firstCRCChar = (firstCRCChar - 55) * 16;
            else firstCRCChar = (firstCRCChar - 48) * 16;
            
            if (secondCRCChar > 64) secondCRCChar = secondCRCChar - 55;
            else secondCRCChar = secondCRCChar - 48;
            
            crcInString = firstCRCChar + secondCRCChar;
            break;
        }
        
        calculatedCrc = calculatedCrc ^ digit;
        
        i++;
    }
    
    if (DEBUG_CRC_CHECK)
    {
        if (crcInString == calculatedCrc) NSLog(@"%s. CRC matches.", __FUNCTION__);
        else NSLog(@"%s. CRC does not match.\nCalculated CRC is 0x%.2X. NMEA sentence is: %@", __FUNCTION__, calculatedCrc, sentence);
    }
    
    if (crcInString != calculatedCrc) return;
    
    // Break the data into an array of elements
    elementsInSentence = [sentence componentsSeparatedByString:@","];
    
    // Parse the data based on the NMEA sentence identifier
    if ([[elementsInSentence objectAtIndex:0] isEqualToString:@"PGGA"])
    {
        // Case 2: parse the location info
        if (DEBUG_PGGA_INFO)
        {
            NSLog(@"%s. PGGA sentence with location info.", __FUNCTION__);
            NSLog(@"%s. buffer text = %s", __FUNCTION__, pLine);
        }
        
        if ([elementsInSentence count] < 10) return;    // malformed sentence
        
        // extract the number of satellites in use by the GPS
        if (DEBUG_PGGA_INFO) NSLog(@"%s. PGGA num of satellites in use = %@.", __FUNCTION__, [elementsInSentence objectAtIndex:7]);
        
        // extract the altitude
        self.alt = [NSNumber numberWithFloat:[[elementsInSentence objectAtIndex:9] floatValue]];
        if (DEBUG_PGGA_INFO) NSLog(@"%s. altitude = %.1f.", __FUNCTION__, [self.alt floatValue]);
        
        // trigger a notification to the view controllers that the satellite data has been updated
        //NSNotification *posDataUpdated = [NSNotification notificationWithName:@"DeviceDataUpdated" object:self];
        //[[NSNotificationCenter defaultCenter] postNotification:posDataUpdated];
    }
    else if (strncmp((char *)pLine, "PGSV", 4) == 0)
    {
        // Case 3: parse the satellite info.
        if (DEBUG_PGSV_INFO) NSLog(@"%s. buffer text = %s.", __FUNCTION__, pLine);
        
        if ([elementsInSentence count] < 4) return;    // malformed sentence
        
        self.numOfGPSSatInView = [NSNumber numberWithInt:[[elementsInSentence objectAtIndex:3] intValue]];
        if (DEBUG_PGSV_INFO) NSLog(@"%s. number of GPS satellites in view = %d.", __FUNCTION__, [self.numOfGPSSatInView intValue]);
        
        // handle the case of the uBlox chip returning no satellites
        if ([self.numOfGPSSatInView intValue] == 0)
        {
            [self.dictOfGPSSatInfo removeAllObjects];
        }
        else
        {
            // If this is first GSV sentence, reset the dictionary of satellite info
            if ([[elementsInSentence objectAtIndex:2] intValue] == 1) [self.dictOfGPSSatInfo removeAllObjects];
            
            NSNumber *satNum, *satElev, *satAzi, *satSNR, *inUse;
            NSMutableArray *satInfo;
            
            // The number of satellites described in a sentence can vary up to 4.
            int numOfSatsInSentence;
            
            if ([elementsInSentence count] == 8) numOfSatsInSentence = 1;
            else if ([elementsInSentence count] == 12) numOfSatsInSentence = 2;
            else if ([elementsInSentence count] == 16) numOfSatsInSentence = 3;
            else if ([elementsInSentence count] == 20) numOfSatsInSentence = 4;
            else return;       // malformed sentence
            
            for (int i=0; i<numOfSatsInSentence; i++)
            {
                int index = i*4 + 4;
                inUse = [NSNumber numberWithBool:NO];
                
                satNum = [NSNumber numberWithInt:[[elementsInSentence objectAtIndex:index] intValue]];
                satElev = [NSNumber numberWithInt:[[elementsInSentence objectAtIndex:(index+1)] intValue]];
                satAzi = [NSNumber numberWithInt:[[elementsInSentence objectAtIndex:(index+2)] intValue]];
                // The stream data will not contain a comma after the last value and before the checksum.
                // So, for example, this sentence can occur:
                //	  PGSV,3,3,10,04,12,092,,21,06,292,29*73
                // But if the last SNR value is NULL, the device will skip the comma separator and
                // just append the checksum. For example, this sentence can occur if the SNR value for the last
                // satellite in the sentence is 0:
                //    PGSV,3,3,10,15,10,189,,13,00,033,*7F
                // The SNR value for the second satellite is NULL, but unlike the same condition with the first
                // satellite, the sentence does not include two commas with nothing between them (to indicate NULL).
                // All of that said, the line below handles the conversion properly.
                satSNR = [NSNumber numberWithFloat:[[elementsInSentence objectAtIndex:(index+3)] floatValue]];
                
                // On random occasions, either the data is bad or the parsing fails. Handle any not-a-number conditions.
                if (isnan([satSNR floatValue]) != 0) satSNR = [NSNumber numberWithFloat:0.0];
                
                for (NSNumber *n in self.gpsSatsUsedInPosCalc)
                {
                    if ([n intValue] == [satNum intValue])
                    {
                        inUse = [NSNumber numberWithBool:YES];
                        break;
                    }
                }
                satInfo = [NSMutableArray arrayWithObjects:satAzi, satElev, satSNR, inUse, nil];
                
                [self.dictOfGPSSatInfo setObject:satInfo forKey:satNum];
            }
            
            // It can take multiple PGSV sentences to deliver all of the satellite data. Update the UI after
            // the last of the data arrives. If the current PGSV sentence number (2nd element in the sentence)
            // is equal to the total number of PGSV messages (1st element in the sentence), that means you have received
            // the last of the satellite data.
            if ([[elementsInSentence objectAtIndex:2] intValue] == [[elementsInSentence objectAtIndex:1] intValue])
            {
                // print the captured data
                if (DEBUG_PGSV_INFO)
                {
                    NSMutableArray *satNums, *satData;
                    satNums = [NSMutableArray arrayWithArray:[self.dictOfGPSSatInfo allKeys]];
                    
                    // sort the array of satellites in numerical order
                    NSSortDescriptor *sorter = [[NSSortDescriptor alloc] initWithKey:@"intValue" ascending:YES];
                    [satNums sortUsingDescriptors:[NSArray arrayWithObject:sorter]];
                    
                    for (int i=0; i<[satNums count]; i++)
                    {
                        satData = [self.dictOfGPSSatInfo objectForKey:[satNums objectAtIndex:i]];
                        NSLog(@"%s. SatNum=%d. Elev=%d. Azi=%d. SNR=%d. inUse=%@", __FUNCTION__,
                              [[satNums objectAtIndex:i] intValue],
                              [[satData objectAtIndex:0] intValue],
                              [[satData objectAtIndex:1] intValue],
                              [[satData objectAtIndex:2] intValue],
                              ([[satData objectAtIndex:3] boolValue])?@"Yes":@"No");
                    }
                }
                
                // Post a notification to the view controllers that the satellite data has been updated
                //NSNotification *satDataUpdated = [NSNotification notificationWithName:@"GPSSatelliteDataUpdated" object:self];
                //[[NSNotificationCenter defaultCenter] postNotification:satDataUpdated];
            }
        }
    }
    else if (strncmp((char *)pLine, "LGSV", 4) == 0)
    {
        // Case 3: parse the satellite info.
        if (DEBUG_LGSV_INFO) NSLog(@"%s. buffer text = %s.", __FUNCTION__, pLine);
        
        if ([elementsInSentence count] < 10) return;    // malformed sentence
        
        self.numOfGLONASSSatInView = [NSNumber numberWithInt:[[elementsInSentence objectAtIndex:3] intValue]];
        if (DEBUG_LGSV_INFO) NSLog(@"%s. number of GLONASS satellites in view = %d.", __FUNCTION__, [self.numOfGLONASSSatInView intValue]);
        
        // handle the case of the uBlox chip returning no satellites
        if ([self.numOfGLONASSSatInView intValue] == 0)
        {
            [self.dictOfGLONASSSatInfo removeAllObjects];
        }
        else
        {
            // If this is first GSV sentence, reset the dictionary of satellite info
            if ([[elementsInSentence objectAtIndex:2] intValue] == 1) [self.dictOfGLONASSSatInfo removeAllObjects];
            
            NSNumber *satNum, *satElev, *satAzi, *satSNR, *inUse;
            NSMutableArray *satInfo;
            
            // The number of satellites described in a sentence can vary up to 4.
            int numOfSatsInSentence;
            if ([elementsInSentence count] == 8) numOfSatsInSentence = 1;
            else if ([elementsInSentence count] == 12) numOfSatsInSentence = 2;
            else if ([elementsInSentence count] == 16) numOfSatsInSentence = 3;
            else if ([elementsInSentence count] == 20) numOfSatsInSentence = 4;
            else return;       // malformed sentence
            
            for (int i=0; i<numOfSatsInSentence; i++)
            {
                int index = i*4 + 4;
                inUse = [NSNumber numberWithBool:NO];
                
                satNum = [NSNumber numberWithInt:[[elementsInSentence objectAtIndex:index] intValue]];
                satElev = [NSNumber numberWithInt:[[elementsInSentence objectAtIndex:(index+1)] intValue]];
                satAzi = [NSNumber numberWithInt:[[elementsInSentence objectAtIndex:(index+2)] intValue]];
                // The stream data will not contain a comma after the last value and before the checksum.
                // So, for example, this sentence can occur:
                //	  PGSV,3,3,10,04,12,092,,21,06,292,29*73
                // But if the last SNR value is NULL, the device will skip the comma separator and
                // just append the checksum. For example, this sentence can occur if the SNR value for the last
                // satellite in the sentence is 0:
                //    PGSV,3,3,10,15,10,189,,13,00,033,*7F
                // The SNR value for the second satellite is NULL, but unlike the same condition with the first
                // satellite, the sentence does not include two commas with nothing between them (to indicate NULL).
                // All of that said, the line below handles the conversion properly.
                satSNR = [NSNumber numberWithFloat:[[elementsInSentence objectAtIndex:(index+3)] floatValue]];
                
                // On random occasions, either the data is bad or the parsing fails. Handle any not-a-number conditions.
                if (isnan([satSNR floatValue]) != 0) satSNR = [NSNumber numberWithFloat:0.0];
                
                for (NSNumber *n in self.glonassSatsUsedInPosCalc)
                {
                    if ([n intValue] == [satNum intValue])
                    {
                        inUse = [NSNumber numberWithBool:YES];
                        break;
                    }
                }
                satInfo = [NSMutableArray arrayWithObjects:satAzi, satElev, satSNR, inUse, nil];
                
                [self.dictOfGLONASSSatInfo setObject:satInfo forKey:satNum];
            }
            
            // It can take multiple PGSV sentences to deliver all of the satellite data. Update the UI after
            // the last of the data arrives. If the current PGSV sentence number (2nd element in the sentence)
            // is equal to the total number of PGSV messages (1st element in the sentence), that means you have received
            // the last of the satellite data.
            if ([[elementsInSentence objectAtIndex:2] intValue] == [[elementsInSentence objectAtIndex:1] intValue])
            {
                // print the captured data
                if (DEBUG_LGSV_INFO)
                {
                    NSMutableArray *satNums, *satData;
                    satNums = [NSMutableArray arrayWithArray:[self.dictOfGLONASSSatInfo allKeys]];
                    
                    // sort the array of satellites in numerical order
                    NSSortDescriptor *sorter = [[NSSortDescriptor alloc] initWithKey:@"intValue" ascending:YES];
                    [satNums sortUsingDescriptors:[NSArray arrayWithObject:sorter]];
                    
                    for (int i=0; i<[satNums count]; i++)
                    {
                        satData = [self.dictOfGLONASSSatInfo objectForKey:[satNums objectAtIndex:i]];
                        NSLog(@"%s. SatNum=%d. Elev=%d. Azi=%d. SNR=%d. inUse=%@", __FUNCTION__,
                              [[satNums objectAtIndex:i] intValue],
                              [[satData objectAtIndex:0] intValue],
                              [[satData objectAtIndex:1] intValue],
                              [[satData objectAtIndex:2] intValue],
                              ([[satData objectAtIndex:3] boolValue])?@"Yes":@"No");
                    }
                }
                
                // Post a notification to the view controllers that the satellite data has been updated
                //NSNotification *satDataUpdated = [NSNotification notificationWithName:@"GLONASSSatelliteDataUpdated" object:self];
                //[[NSNotificationCenter defaultCenter] postNotification:satDataUpdated];
            }
        }
    }
    else if (strncmp((char *)pLine, "PGSA", 4) == 0)
    {
        // Case 4: parse the dilution of precision info. Sentence will look like:
        //		eg1. PGSA,A,1,,,,,,,,,,,,,0.0,0.0,0.0*30
        //		eg2. PGSA,A,3,24,14,22,31,11,,,,,,,,3.7,2.3,2.9*3D
        //
        // Skytraq chipset:
        // e.g. PGSA,A,1,,,,,,,,,,,,,0.0,0.0,0.0*30     (no signal)
        //
        // uBlox chipset:
        // e.g. PGSA,A,1,,,,,,,,,,,,,99.99,99.99,99.99*30      (no signal)
        //      PGSA,A,3,02,29,13,12,48,10,25,05,,,,,3.93,2.06,3.35*0D
        
        // NGSA sentence will contain identical fix type and DOP information.
        
        /* Wikipedia (http://en.wikipedia.org/wiki/Dilution_of_precision_(GPS)) has a good synopsis on how to interpret
         DOP values:
         
         DOP Value	Rating		Description
         ---------	---------	----------------------
         1			Ideal		This is the highest possible confidence level to be used for applications demanding
         the highest possible precision at all times.
         1-2		Excellent	At this confidence level, positional measurements are considered accurate enough to meet
         all but the most sensitive applications.
         2-5		Good		Represents a level that marks the minimum appropriate for making business decisions.
         Positional measurements could be used to make reliable in-route navigation suggestions to
         the user.
         5-10		Moderate	Positional measurements could be used for calculations, but the fix quality could still be
         improved. A more open view of the sky is recommended.
         10-20		Fair		Represents a low confidence level. Positional measurements should be discarded or used only
         to indicate a very rough estimate of the current location.
         >20		Poor		At this level, measurements are inaccurate by as much as 300 meters and should be discarded.
         
         */
        
        if (DEBUG_PGSA_INFO)
        {
            NSLog(@"%s. sentence contains DOP info.", __FUNCTION__);
            NSLog(@"%s. buffer text = %s.", __FUNCTION__, pLine);
        }
        
        if ([elementsInSentence count] < 18) return;    // malformed sentence
        
        // extract whether the fix type is 1=no fix, 2=2D fix or 3=3D fix
        self.fixType = [NSNumber numberWithInt:[[elementsInSentence objectAtIndex:2] intValue]];
        if (DEBUG_PGSA_INFO) NSLog(@"%s. fix value = %d.", __FUNCTION__, [self.fixType intValue]);
        
        // extract PDOP
        self.pdop = [NSNumber numberWithFloat:[[elementsInSentence objectAtIndex:15] floatValue]];
        if (DEBUG_PGSA_INFO) NSLog(@"%s. PDOP value = %f.", __FUNCTION__, [self.pdop floatValue]);
        
        // extract HDOP
        self.hdop = [NSNumber numberWithFloat:[[elementsInSentence objectAtIndex:16] floatValue]];
        if (DEBUG_PGSA_INFO) NSLog(@"%s. HDOP value = %f.", __FUNCTION__, [self.hdop floatValue]);
        
        // extract VDOP
        self.vdop = [NSNumber numberWithFloat:[[elementsInSentence objectAtIndex:17] floatValue]];
        if (DEBUG_PGSA_INFO) NSLog(@"%s. VDOP value = %f.", __FUNCTION__, [self.vdop floatValue]);
        
        // extract the number of satellites used in the position fix calculation
        NSString *satInDOP;
        NSMutableArray *satsInDOPCalc = [[NSMutableArray alloc] init];
        self.waasInUse = NO;
        for (int i=3; i<15; i++)
        {
            satInDOP = [elementsInSentence objectAtIndex:i];
            if ([satInDOP length] > 0)
            {
                [satsInDOPCalc addObject:satInDOP];
                if ([satInDOP intValue] > 32) self.waasInUse = YES;
            }
            satInDOP = nil;
        }
        self.numOfGPSSatInUse = [NSNumber numberWithUnsignedInteger:[satsInDOPCalc count]];
        self.gpsSatsUsedInPosCalc = satsInDOPCalc;
        
        if (DEBUG_PGSA_INFO)
        {
            NSLog(@"%s. # of satellites used in DOP calc: %d", __FUNCTION__, [self.numOfGPSSatInUse intValue]);
            NSMutableString *logTxt = [NSMutableString stringWithString:@"Satellites used in DOP calc: "];
            for (NSString *s in self.gpsSatsUsedInPosCalc)
            {
                [logTxt appendFormat:@"%@, ", s];
            }
            NSLog(@"%s. %@", __FUNCTION__, logTxt);
        }
        
        satsInDOPCalc = nil;
    }
    else if (strncmp((char *)pLine, "NGSA", 4) == 0)
    {
        // NGSA sentence will contain identical fix type and DOP information. So only the satellite data is useful
        // in this sentence.
        
        if ([elementsInSentence count] < 18) return;    // malformed sentence
        
        // extract the number of satellites used in the position fix calculation
        NSString *satInDOP;
        NSMutableArray *satsInDOPCalc = [[NSMutableArray alloc] init];
        for (int i=3; i<15; i++)
        {
            satInDOP = [elementsInSentence objectAtIndex:i];
            if ([satInDOP length] > 0) [satsInDOPCalc addObject:satInDOP];
            satInDOP = nil;
        }
        self.numOfGLONASSSatInUse = [NSNumber numberWithUnsignedInteger:[satsInDOPCalc count]];
        self.glonassSatsUsedInPosCalc = satsInDOPCalc;
        
        if (DEBUG_NGSA_INFO)
        {
            NSLog(@"%s. # of satellites used in DOP calc: %d", __FUNCTION__, [self.numOfGLONASSSatInUse intValue]);
            NSMutableString *logTxt = [NSMutableString stringWithString:@"Satellites used in DOP calc: "];
            for (NSString *s in self.glonassSatsUsedInPosCalc)
            {
                [logTxt appendFormat:@"%@, ", s];
            }
            NSLog(@"%s. %@", __FUNCTION__, logTxt);
        }
        
        satsInDOPCalc = nil;
    }
    else if (strncmp((char *)pLine, "PRMC", 4) == 0)
    {
        // Case 6: extract whether the speed and course data are valid, as well as magnetic deviation
        //		eg1. PRMC,220316.000,V,2845.7226,N,08121.9825,W,000.0,000.0,220311,,,N*65
        //		eg2. PRMC,220426.988,A,2845.7387,N,08121.9957,W,000.0,246.2,220311,,,A*7C
        //
        // Skytraq chipset:
        // e.g. PRMC,120138.000,V,0000.0000,N,00000.0000,E,000.0,000.0,280606,,,N*75   (no signal)
        //
        //
        // uBlox chipset:
        // e.g. PRMC,,V,,,,,,,,,,N*53      (no signal)
        //      PRMC,162409.00,A,2845.73357,N,08121.99127,W,0.911,39.06,281211,,,D*4D
        
        if (DEBUG_PRMC_INFO)
        {
            NSLog(@"%s. sentence contains speed & course info.", __FUNCTION__);
            NSLog(@"%s. buffer text = %s.", __FUNCTION__, pLine);
        }
        
        if ([elementsInSentence count] < 9) return;     // malformed sentence
        
        // extract the time the coordinate was captured. UTC time format is hhmmss.ss
        NSString *timeStr, *hourStr, *minStr, *secStr;
        
        timeStr = [elementsInSentence objectAtIndex:1];
        // Check for malformed data. NMEA 0183 spec says minimum 2 decimals for seconds: hhmmss.ss
        if ([timeStr length] < 9) return;   // malformed data
        
        hourStr = [timeStr substringWithRange:NSMakeRange(0,2)];
        minStr = [timeStr substringWithRange:NSMakeRange(2,2)];
        secStr = [timeStr substringWithRange:NSMakeRange(4,5)];
        self.utc = [NSString stringWithFormat:@"%@:%@:%@", hourStr, minStr, secStr];
        if (DEBUG_PRMC_INFO) NSLog(@"%s. UTC Time is %@.", __FUNCTION__, self.utc);
        
        // is the track and course data valid? An "A" means yes, and "V" means no.
        NSString *valid = [elementsInSentence objectAtIndex:2];
        if ([valid isEqualToString:@"A"]) self.speedAndCourseIsValid = YES;
        else self.speedAndCourseIsValid = NO;
        if (DEBUG_PRMC_INFO) NSLog(@"%s. speed & course data valid: %d.", __FUNCTION__, self.speedAndCourseIsValid);
        
        // extract latitude info
        // ex:	"4124.8963, N" which equates to 41d 24.8963' N or 41d 24' 54" N
        float mins;
        int deg, sign;
        double lat, lon;
        
        if ([[elementsInSentence objectAtIndex:3] length] == 0)
        {
            // uBlox chip special case
            deg = 0;
            mins = 0.0;
        }
        // Check for corrupted data. The NMEA spec says latitude needs at least 4 digits in front of the decimal, and 2 after.
        else if ([[elementsInSentence objectAtIndex:3] length] < 7) return;
        else
        {
            sign = 1;
            lat = [[elementsInSentence objectAtIndex:3] doubleValue];
            if (DEBUG_PRMC_INFO) NSLog(@"latitude text = %@. converstion to float = %f.", [elementsInSentence objectAtIndex:3], lat);
            deg = (int)(lat / 100);
            mins = (lat - (100 * (float)deg)) / 60.0;
            if (DEBUG_PRMC_INFO) NSLog(@"degrees = %d. mins = %.5f.", deg, mins);
            
            if ([[elementsInSentence objectAtIndex:4] isEqualToString:@"S"]) sign = -1;   // capture the "N" or "S"
        }
        self.lat = [NSNumber numberWithFloat:(deg + mins)*sign];
        if (DEBUG_PRMC_INFO) NSLog(@"%s. latitude = %.5f", __FUNCTION__, [self.lat floatValue]);
        
        // extract longitude info
        // ex: "08151.6838, W" which equates to	81d 51.6838' W or 81d 51' 41" W
        if ([[elementsInSentence objectAtIndex:5] length] == 0)
        {
            // uBlox chip special case
            deg = 0;
            mins = 0.0;
        }
        // Check for corrupted data. The NMEA spec says latitude needs at least 5 digits in front of the decimal, and 2 after.
        else if ([[elementsInSentence objectAtIndex:3] length] < 8) return;
        else
        {
            sign = 1;
            lon = [[elementsInSentence objectAtIndex:5] doubleValue];
            if (DEBUG_PRMC_INFO) NSLog(@"longitude text = %@. converstion to float = %f.", [elementsInSentence objectAtIndex:5], lon);
            deg = (int)(lon / 100);
            mins = (lon - (100 * (float)deg)) / 60.0;
            if (DEBUG_PRMC_INFO) NSLog(@"degrees = %d. mins = %.5f.", deg, mins);
            
            if ([[elementsInSentence objectAtIndex:6] isEqualToString:@"W"]) sign = -1;   // capture the "E" or "W"
        }
        self.lon = [NSNumber numberWithFloat:(deg + mins)*sign];
        if (DEBUG_PRMC_INFO) NSLog(@"%s. longitude = %.5f", __FUNCTION__, [self.lon floatValue]);
        
        // Pull the speed information from the RMC sentence since this updates at the fast refresh rate in the Skytraq chipset
        if ([[elementsInSentence objectAtIndex:7] isEqualToString:@""]) self.speedKnots = [NSNumber numberWithFloat:0.0];
        else self.speedKnots = [NSNumber numberWithFloat:[[elementsInSentence objectAtIndex:7] floatValue]];
        self.speedKph = [NSNumber numberWithFloat:([self.speedKnots floatValue] * 1.852)];
        if (DEBUG_PRMC_INFO) NSLog(@"%s. knots = %.1f. kph = %.1f.", __FUNCTION__, [self.speedKnots floatValue], [self.speedKph floatValue]);
        
        // Extract the course heading
        if ([[elementsInSentence objectAtIndex:8] isEqualToString:@""]) self.trackTrue = [NSNumber numberWithFloat:0.0];
        else self.trackTrue = [NSNumber numberWithFloat:[[elementsInSentence objectAtIndex:8] floatValue]];
        if (DEBUG_PRMC_INFO) NSLog(@"%s. true north course = %.1f.", __FUNCTION__, [self.trackTrue floatValue]);
        
        // trigger a notification to the view controllers that the satellite data has been updated
        NSNotification *posDataUpdated = [NSNotification notificationWithName:@"PositionDataUpdated" object:self];
        [[NSNotificationCenter defaultCenter] postNotification:posDataUpdated];
        
    }
}

#pragma mark - Application lifecycle methods
- (void)observeNotifications
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(queueConnectNotifications:)
                                                 name:EAAccessoryDidConnectNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(queueDisconnectNotifications:)
                                                 name:EAAccessoryDidDisconnectNotification
                                               object:nil];
    
    // Register for notifications from the iOS that accessories are connecting or disconnecting
    [[EAAccessoryManager sharedAccessoryManager] registerForLocalNotifications];
}

- (void)stopObservingNotifications
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:EAAccessoryDidConnectNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:EAAccessoryDidDisconnectNotification object:nil];
    [[EAAccessoryManager sharedAccessoryManager] unregisterForLocalNotifications];
}

- (id)init
{
    if ((self = [super init]))
    {
        self.isConnected = NO;
        self.firmwareRev = @"";
        self.serialNumber = @"";
        self.batteryVoltage = 0;
        self.isCharging = NO;
        self.streamingMode = YES;
        
        self.arr_logListEntries = [[NSMutableArray alloc] init];
        self.arr_logDataSamples = [[NSMutableArray alloc] init];
        
        self.logListItemTimerStarted = NO;
        self.newLogListItemReceived = NO;
        
        self.deviceSettingsHaveBeenRead = NO;
        
        totalGPSSamplesInLogEntry = 0;
        
        // Watch for local accessory connect & disconnect notifications.
        [self observeNotifications];
        
        // Check to see if device is attached.
        if ([self isXGPS160AnAvailableAccessory]) [self openSession];
    }
    
    return self;
}

#pragma mark - BT Connection Management Methods
#pragma mark • Application lifecycle methods

- (void)xgps160_applicationWillResignActive
{
    /*
     Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
     Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
     */
    
    // NOTE: this method is called when:
    //		- when a dialog box (like an alert view) opens.
    //		- by a double-tap on the home button to bring up the multitasking menu
    //		- when the iPod/iPad/iPhone goes to sleep (manually or after the timer runs out)
    //		- when app exits becuase the home button is tapped (once)
    
    // Close any open streams. The OS sends a false "Accessory Disconnected" message when the home button is double tapped
    // to bring up the mutitasking menu. So the safest thing is to disconnect from the xgps160 when that happens, and reconnect
    // later.
    [self closeSession];
    
    // stop watching for Accessory notifications
    [self stopObservingNotifications];
}


- (void)xgps160_applicationDidEnterBackground
{
    // NOTE: this method is called when:
    //		- another app takes forefront.
    //		- after applicationWillResignActive in response to the home button is tapped (once)
    
    // Close any open streams
    [self closeSession];
    
    // stop watching for Accessory notifications
    [self stopObservingNotifications];
}

- (void)xgps160_applicationWillEnterForeground
{
    // Called as part of the transition from the background to the inactive state: here you can undo many of the changes
    // made on entering the background.
    
    // NOTE: this method is called:
    //		- when an app icon is already running in the background, and the app icon is clicked to resume the app
    
    // Begin watching for Accessory notifications again. Do this first because the rest of the method may complete before
    // the accessory reconnects.
    [self observeNotifications];
    
    // Recheck to see if the xgps160 disappeared while away
    if (self.isConnected == NO)
    {
        if ([self isXGPS160AnAvailableAccessory]) [self openSession];
    }
}

- (void)xgps160_applicationDidBecomeActive
{
    // Restart any tasks that were paused (or not yet started) while the application was inactive.
    // If the application was previously in the background, optionally refresh the user interface.
    
    // NOTE: this method is called:
    //		- when an app first opens
    //		- when an app is running & the iPod/iPad/iPhone goes to sleep and is then reawoken, e.g. when the app is
    //		  running->iPod/iPad/iPhone goes to sleep (manually or by the timer)->iPod/iPad/iPhone is woken up & resumes the app
    //		- when the app is resumed from when the multi-tasking menu is opened (in the scenario where the
    //		  app was running, the multitasking menu opened by a double-tap of the home button, followed by a tap on the screen to
    //		  resume the app.)
    
    // begin watching for Accessory notifications again
    [self observeNotifications];
    
    // Recheck to see if the xgps160 disappeared while away
    if (self.isConnected == NO)
    {
        if ([self isXGPS160AnAvailableAccessory]) [self openSession];
    }
    
    // NOTE: if the iPod/iPad/iPhone goes to sleep while a view controller is open, there is no notification
    // that the app is back to life, other than this applicationDidBecomeActive method being called. The viewWillAppear,
    // viewDidAppear, or viewDidOpen methods are not triggered when the iPod/iPad/iPhone is woken and the app resumes.
    // Consequently, notify the view controllers in case they need to adjust their UI if the xgps160 status changed
    // while the iPod/iPad/iPhone was asleep.
    NSNotification *notification = [NSNotification notificationWithName:@"RefreshUIAfterAwakening" object:self];
    [[NSNotificationCenter defaultCenter] postNotification:notification];
}

- (void)xgps160_applicationWillTerminate
{
    // Called when the application is about to terminate. See also applicationDidEnterBackground:.
    
    // Close session with xgps160
    [self closeSession];
    
    // stop watching for Accessory notifications
    [self stopObservingNotifications];
}

#pragma mark • Session Management Methods
// open a session with the accessory and set up the input and output stream on the default run loop
- (bool)openSession
{
    if (self.isConnected) return YES;
    
    [self.accessory setDelegate:self];
    self.session = [[EASession alloc] initWithAccessory:self.accessory forProtocol:self.protocolString];
    
    if (self.session)
    {
        [[self.session inputStream] setDelegate:self];
        [[self.session inputStream] scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        [[self.session inputStream] open];
        
        [[self.session outputStream] setDelegate:self];
        [[self.session outputStream] scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        [[self.session outputStream] open];
        
        self.isConnected = YES;
        
        // Read device settings
        [self performSelector:@selector(readDeviceSettings) withObject:nil afterDelay:kReadDeviceSettingAfterDelay];
    }
    else
    {
        //NSLog(@"Session creation failed");
        self.accessory = nil;
        self.accessoryConnectionID = 0;
        self.protocolString = nil;
    }
    
    return (self.session != nil);
    
}

// close the session with the accessory.
- (void)closeSession
{
    // Closing the streams and releasing session disconnects the app from the XGPS160, but it does not disconnect
    // the XGPS160 from Bluetooth. In other words, the communication streams close, but the device stays
    // registered with the OS as an available accessory.
    //
    // The OS can report that the device has disconnected in two different ways: either that the stream has
    // ended or that the device has disconnected. Either event can happen first, so this method is called
    // in response to a NSStreamEndEventEncountered (from method -stream:handlevent) or in response to an
    // EAAccessoryDidDisconnectNotification (from method -accessoryDisconnected). It seems that the speed of
    // the Apple device being used, e.g. iPod touch gen 2 vs. iPad, affects which event occurs first.
    // Turning off the power on the XGPS160 tends to cause the NSStreamEndEventEncountered to occur
    // before the EAAccessoryDidDisconnectNotification.
    //
    // Note also that a EAAccessoryDidDisconnectNotification is generated when the home button
    // is tapped (bringing up the multitasking menu) beginning in iOS 5.
    
    if (self.session == nil) return;
    
    [[self.session inputStream] removeFromRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
    [[self.session inputStream] close];
    [[self.session inputStream] setDelegate:nil];
    
    [[self.session outputStream] removeFromRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
    [[self.session outputStream] close];
    [[self.session outputStream] setDelegate:nil];
    
    self.session = nil;
    self.isConnected = NO;
    
    self.accessory = nil;
    self.accessoryConnectionID = 0;
    self.protocolString = nil;
}

- (bool)isXGPS160AnAvailableAccessory
{
    bool	connect = NO;
    
    if (self.isConnected) return YES;
    
    // get the list of all attached accessories (30-pin or bluetooth)
    NSArray *attachedAccessories = [[EAAccessoryManager sharedAccessoryManager] connectedAccessories];
    
    for (EAAccessory *obj in attachedAccessories)
    {
        if ([[obj protocolStrings] containsObject:@"com.dualav.xgps150"])
        {
            // At this point, the xgps160 has a BT connection to the iPod/iPad/iPhone, but the communication streams
            // have not been opened yet
            connect = YES;
            self.firmwareRev = [NSString stringWithString:[obj firmwareRevision]];
            self.serialNumber = [NSString stringWithString:[obj serialNumber]];
            
            self.accessory = obj;
            self.accessoryConnectionID = obj.connectionID;
            self.protocolString = @"com.dualav.xgps150";
        }
    }
    
    if (!connect)
    {
        //NSLog(@"%s. XGPS160 NOT detected.", __FUNCTION__);
        self.firmwareRev = NULL;
        self.serialNumber = NULL;
        
        self.accessory = nil;
        self.accessoryConnectionID = 0;
        self.protocolString = nil;
    }
    
    return connect;
}

#pragma mark • Accessory watchdog methods
/* When the xgps160 connects after being off, the iOS generates a very rapid seqeunce of connect-disconnect-connect
 events. The solution is wait until all of the notifications have come in, and process the last one.
 */
- (void)processConnectionNotifications
{
    queueTimerStarted = NO;
    
    if (self.notificationType)   // last notification was to connect
    {
        if ([self isXGPS160AnAvailableAccessory] == YES)
        {
            if ([self openSession] == YES)
            {
                // Notify the view controllers that the xgps160 is connected and streaming data
                NSNotification *notification = [NSNotification notificationWithName:@"XGPS160Connected" object:self];
                [[NSNotificationCenter defaultCenter] postNotification:notification];
            }
        }
    }
    else    // last notification was a disconnect
    {
        // The iOS can send a false disconnect notification when the home button is double-tapped
        // to enter the multitasking menu. So in the event of a EAAccessoryDidDisconnectNotification, double
        // check that the device is actually gone before disconnecting from the xgps160.
        if (self.accessory.connected == YES) return;
        else
        {
            [self closeSession];
            
            // Notify the view controllers that the xgps160 disconnected
            NSNotification *notification = [NSNotification notificationWithName:@"XGPS160Disconnected" object:self];
            [[NSNotificationCenter defaultCenter] postNotification:notification];
        }
    }
    
}

- (void)queueDisconnectNotifications:(NSNotification *)notification
{
    // Make sure it was the XGPS160 that disconnected
    if (self.accessory == nil)       // XGPS160 not connected
    {
        return;
    }
    
    EAAccessory *eak = [[notification userInfo] objectForKey:EAAccessoryKey];
    if (eak.connectionID != self.accessoryConnectionID)  // wasn't the XGPS160 that disconnected
    {
        return;
    }
    
    // It was an XGPS150/160 that disconnected
    self.mostRecentNotification = notification;
    self.notificationType = NO;
    
    if (queueTimerStarted == NO)
    {
        [self performSelector:@selector(processConnectionNotifications) withObject:nil afterDelay:kProcessTimerDelay];
        queueTimerStarted = YES;
    }
}

- (void)queueConnectNotifications:(NSNotification *)notification
{
    // Make sure it was the XGPS150/160 that connected
    EAAccessory *eak = [[notification userInfo] objectForKey:EAAccessoryKey];
    if ([[eak protocolStrings] containsObject:@"com.dualav.xgps150"])       // yes, an XGPS150/160 connected
    {
        self.mostRecentNotification = notification;
        self.notificationType = YES;
        
        if (queueTimerStarted == NO)
        {
            [self performSelector:@selector(processConnectionNotifications) withObject:nil afterDelay:kProcessTimerDelay];
            queueTimerStarted = YES;
        }
    }
    else        // It wasn't an XGPS150/160 that connected, or the correct protocols weren't included in the connect notification.
        // Note: it is normal for no protocols to be included in the first accessory connection notification. It's a iOS thing.
    {
        return;
    }
}
@end
