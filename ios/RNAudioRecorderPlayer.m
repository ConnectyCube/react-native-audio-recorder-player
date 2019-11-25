//  RNAudioRecorderPlayer.m
//  dooboolab
//
//  Created by dooboolab on 16/04/2018.
//  Copyright © 2018 Facebook. All rights reserved.
//

#import "RNAudioRecorderPlayer.h"
#import <React/RCTLog.h>
#import <AVFoundation/AVFoundation.h>

@implementation RNAudioRecorderPlayer {
  NSURL *audioFileURL;
  AVAudioRecorder *audioRecorder;
  AVAudioPlayer *audioPlayer;
  NSTimer *recordTimer;
  NSTimer *playTimer;
}
double subscriptionDuration = 0.1;

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag {
  NSLog(@"audioPlayerDidFinishPlaying");
  NSNumber *duration = [NSNumber numberWithDouble:audioPlayer.duration * 1000];
  NSNumber *currentTime = [NSNumber numberWithDouble:audioPlayer.duration * 1000];

  // Send last event then finish it.
  // NSString* status = [NSString stringWithFormat:@"{\"duration\": \"%@\", \"current_position\": \"%@\"}", [duration stringValue], [currentTime stringValue]];
  NSDictionary *status = @{
                         @"duration" : [duration stringValue],
                         @"current_position" : [duration stringValue],
                         };
  [self sendEventWithName:@"rn-playback" body: status];
  if (playTimer != nil) {
    [playTimer invalidate];
    playTimer = nil;
  }
}

- (void)updateRecorderProgress:(NSTimer*) timer
{
  NSNumber *currentTime = [NSNumber numberWithDouble:audioRecorder.currentTime * 1000];
  // NSString* status = [NSString stringWithFormat:@"{\"current_position\": \"%@\"}", [currentTime stringValue]];
  NSDictionary *status = @{
                         @"current_position" : [currentTime stringValue],
                         };
  [self sendEventWithName:@"rn-recordback" body:status];
}

- (void)updateProgress:(NSTimer*) timer
{
  NSNumber *duration = [NSNumber numberWithDouble:audioPlayer.duration * 1000];
  NSNumber *currentTime = [NSNumber numberWithDouble:audioPlayer.currentTime * 1000];

  NSLog(@"updateProgress: %@", duration);

  if ([duration intValue] == 0) {
    [playTimer invalidate];
    [audioPlayer stop];
    return;
  }

  // NSString* status = [NSString stringWithFormat:@"{\"duration\": \"%@\", \"current_position\": \"%@\"}", [duration stringValue], [currentTime stringValue]];
  NSDictionary *status = @{
                         @"duration" : [duration stringValue],
                         @"current_position" : [currentTime stringValue],
                         };

  [self sendEventWithName:@"rn-playback" body:status];
}

- (void)startRecorderTimer
{
  dispatch_async(dispatch_get_main_queue(), ^{
      self->recordTimer = [NSTimer scheduledTimerWithTimeInterval: subscriptionDuration
                                           target:self
                                           selector:@selector(updateRecorderProgress:)
                                           userInfo:nil
                                           repeats:YES];
  });
}

- (void)startPlayerTimer
{
  dispatch_async(dispatch_get_main_queue(), ^{
      self->playTimer = [NSTimer scheduledTimerWithTimeInterval: subscriptionDuration
                                           target:self
                                           selector:@selector(updateProgress:)
                                           userInfo:nil
                                           repeats:YES];
  });
}

- (dispatch_queue_t)methodQueue
{
    return dispatch_get_main_queue();
}

RCT_EXPORT_MODULE();

- (NSArray<NSString *> *)supportedEvents
{
  return @[@"rn-recordback", @"rn-playback"];
}

RCT_EXPORT_METHOD(requestRecordPermission:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    NSLog(@"[requestRecordPermission]");
    switch ([[AVAudioSession sharedInstance] recordPermission]) {
        case AVAudioSessionRecordPermissionGranted:
            resolve(@"Granted");
            break;
        case AVAudioSessionRecordPermissionDenied:
            reject(@"[requestRecordPermission]", @"Denied", nil);
            break;
        case AVAudioSessionRecordPermissionUndetermined: {
            [[AVAudioSession sharedInstance] requestRecordPermission:^(BOOL granted) {
                if (granted) {
                    resolve(@"Granted");
                } else {
                    reject(@"[requestRecordPermission]", @"Denied", nil);
                }
            }];
            break;
        }
        default:
            break;
    }
}

RCT_EXPORT_METHOD(setSubscriptionDuration:(double)duration
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
  subscriptionDuration = duration;
  resolve(@"set subscription duration.");
}

RCT_EXPORT_METHOD(startRecorder:(NSString*)path
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {

  if ([path isEqualToString:@"DEFAULT"]) {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSString* fileNameWithExt = [NSString stringWithFormat:@"/%@.%@", [[NSString stringWithFormat:@"%f", [[NSDate date] timeIntervalSince1970]] stringByReplacingOccurrencesOfString: @"." withString:@""], @"m4a"];
    audioFileURL = [NSURL fileURLWithPath:[documentsDirectory stringByAppendingString: fileNameWithExt]];
    NSLog(@"[Record doc dirt] %@", documentsDirectory);
      NSLog(@"[Record url] %@", audioFileURL);
  } else {
    audioFileURL = [NSURL fileURLWithPath: path];
  }

  NSDictionary *audioSettings = [NSDictionary dictionaryWithObjectsAndKeys:
                                 [NSNumber numberWithFloat:44100],AVSampleRateKey,
                                 [NSNumber numberWithInt: kAudioFormatMPEG4AAC],AVFormatIDKey,
                                 [NSNumber numberWithInt: 2],AVNumberOfChannelsKey,
                                 [NSNumber numberWithInt:AVAudioQualityMedium],AVEncoderAudioQualityKey,nil];

  // Setup audio session
  AVAudioSession *session = [AVAudioSession sharedInstance];
  [session setCategory:AVAudioSessionCategoryPlayAndRecord error:nil];

  // set volume default to speaker
  UInt32 doChangeDefaultRoute = 1;
  AudioSessionSetProperty(kAudioSessionProperty_OverrideCategoryDefaultToSpeaker, sizeof(doChangeDefaultRoute), &doChangeDefaultRoute);

  audioRecorder = [[AVAudioRecorder alloc]
                        initWithURL:audioFileURL
                        settings:audioSettings
                        error:nil];

  [audioRecorder setDelegate:self];
  [audioRecorder record];
  [self startRecorderTimer];

  NSString *filePath = self->audioFileURL.absoluteString;
  resolve(filePath);
}

RCT_EXPORT_METHOD(stopRecorder:(BOOL) cancel
                  resolve: (RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    if (audioRecorder) {
        double duration = audioRecorder.currentTime;
        [audioRecorder stop];
        if (recordTimer != nil) {
            [recordTimer invalidate];
            recordTimer = nil;
        }

        AVAudioSession *audioSession = [AVAudioSession sharedInstance];
        [audioSession setActive:NO error:nil];
        
        NSString *filePath = audioFileURL.path;
        if (cancel) {
            NSLog(@"Cnacel recod path: %@", filePath);
            NSError *error;
            if ([[NSFileManager defaultManager] isDeletableFileAtPath:filePath]) {
                BOOL success = [[NSFileManager defaultManager] removeItemAtPath:filePath error:&error];
                if (!success) {
                    NSLog(@"Error removing file at path: %@", error.localizedDescription);
                }
            } else {
                NSLog(@"Can't remove file at path: %@", error.localizedDescription);
            }
            resolve(@"[stopRecorder] cancel record file");
        } else{
            unsigned long long fileSize = [[[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:nil] fileSize];
            NSLog(@"FileSize %d", fileSize);
            NSLog(@"duration %f", duration);
            NSDictionary* result = @{
                @"path": audioFileURL.absoluteString,
                @"size": @(fileSize),
                @"duration": @(duration * 1000)
            };
            NSLog(@"Stop audio result %@", result);
            resolve(result);
        }
    } else {
        reject(@"audioRecorder record", @"audioRecorder is not set", nil);
    }
}

RCT_EXPORT_METHOD(setVolume:(double) volume
                  resolve:(RCTPromiseResolveBlock) resolve
                  reject:(RCTPromiseRejectBlock) reject) {
    [audioPlayer setVolume: volume];
    resolve(@"setVolume");
}

RCT_EXPORT_METHOD(startPlayer:(NSString*)path
                  seekTo: (double) skeepTo
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    NSError *error;
    if ([[path substringToIndex:4] isEqualToString:@"http"]) {
        audioFileURL = [NSURL URLWithString:path];
        
        NSURLSessionDataTask *downloadTask = [[NSURLSession sharedSession]
        dataTaskWithURL:audioFileURL completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
              // NSData *data = [NSData dataWithContentsOfURL:audioFileURL];
              if (!audioPlayer) {
                  audioPlayer = [[AVAudioPlayer alloc] initWithData:data error:&error];
                  audioPlayer.delegate = self;
              }
              
              // Able to play in silent mode
              [[AVAudioSession sharedInstance]
               setCategory: AVAudioSessionCategoryPlayback
               error: &error];
              // Able to play in background
              [[AVAudioSession sharedInstance] setActive: YES error: nil];
              [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
                if (skeepTo > 0) {
                    audioPlayer.currentTime = skeepTo;
                }
              [audioPlayer play];
              [self startPlayerTimer];
              NSString *filePath = audioFileURL.absoluteString;
              resolve(filePath);
        }];
        
        [downloadTask resume];
    } else {
        if ([path isEqualToString:@"DEFAULT"]) {
            audioFileURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingString:@"sound.m4a"]];
        } else {
            audioFileURL = [NSURL fileURLWithPath:path];
        }

        if (!audioPlayer) {
            RCTLogInfo(@"audio player alloc %@", audioFileURL);
            audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:audioFileURL error:&error];
            audioPlayer.delegate = self;
        }

        NSError *errorSession;
        
        // Able to play in silent mode
        [[AVAudioSession sharedInstance]
            setCategory: AVAudioSessionCategoryPlayback
            error: &errorSession];

        NSLog(@"Error %@",error);
        NSLog(@"Error session %@",errorSession);
        NSLog(@"[Play url] %@", audioFileURL);
        NSLog(@"[Play url] position %f", skeepTo);
        if (skeepTo > 0) {
            audioPlayer.currentTime = skeepTo;
        }
        [audioPlayer play];
        [self startPlayerTimer];

        NSString *filePath = audioFileURL.absoluteString;
        resolve(filePath);
    }
}

RCT_EXPORT_METHOD(resumePlayer: (RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    if (!audioFileURL) {
        reject(@"audioRecorder resume", @"no audioFileURL", nil);
        return;
    }

    if (!audioPlayer) {
        reject(@"audioRecorder resume", @"no audioPlayer", nil);
        return;
    }

    [[AVAudioSession sharedInstance]
        setCategory: AVAudioSessionCategoryPlayback
        error: nil];
    [audioPlayer play];
    [self startPlayerTimer];
    NSString *filePath = audioFileURL.absoluteString;
    resolve(filePath);
}

RCT_EXPORT_METHOD(seekToPlayer: (nonnull NSNumber*) time
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    if (audioPlayer) {
        audioPlayer.currentTime = [time doubleValue];
    } else {
        reject(@"audioPlayer seekTo", @"audioPlayer is not set", nil);
    }
}

RCT_EXPORT_METHOD(pausePlayer: (RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    RCTLogInfo(@"pause");
    if (audioPlayer && [audioPlayer isPlaying]) {
        [audioPlayer pause];
        if (playTimer != nil) {
            [playTimer invalidate];
            playTimer = nil;
        }
        resolve(@"pause play");
    } else {
        reject(@"audioPlayer pause", @"audioPlayer is not playing", nil);
    }
}


RCT_EXPORT_METHOD(stopPlayer:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    if (audioPlayer) {
        if (playTimer != nil) {
            [playTimer invalidate];
            playTimer = nil;
        }
        [audioPlayer stop];
        audioPlayer = nil;
        resolve(@"stop play");
    } else {
        reject(@"audioPlayer stop", @"audioPlayer is not set", nil);
    }
}

@end
