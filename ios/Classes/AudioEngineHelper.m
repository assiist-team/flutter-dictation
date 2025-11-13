#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

BOOL safePrepareAudioEngine(AVAudioEngine *engine, NSError **error) {
    @try {
        [engine prepare];
        return YES;
    }
    @catch (NSException *exception) {
        if (error) {
            *error = [NSError errorWithDomain:@"AudioEngineManager"
                                         code:-1
                                     userInfo:@{
                                         NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to prepare audio engine: %@", exception.name],
                                         NSUnderlyingErrorKey: exception
                                     }];
        }
        return NO;
    }
}

