#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

/// Safely prepares an AVAudioEngine, catching any Objective-C exceptions.
/// - Parameters:
///   - engine: The AVAudioEngine to prepare
///   - error: Pointer to NSError for error reporting
/// - Returns: YES if preparation succeeded, NO otherwise
BOOL safePrepareAudioEngine(AVAudioEngine *engine, NSError **error);

