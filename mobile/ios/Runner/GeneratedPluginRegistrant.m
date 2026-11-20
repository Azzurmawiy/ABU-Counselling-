//
//  Generated file. Do not edit.
//

// clang-format off

#import "GeneratedPluginRegistrant.h"

#if __has_include(<flutter_secure_storage_darwin/FlutterSecureStorageDarwinPlugin.h>)
#import <flutter_secure_storage_darwin/FlutterSecureStorageDarwinPlugin.h>
#else
@import flutter_secure_storage_darwin;
#endif

#if __has_include(<google_mlkit_commons/GoogleMlKitCommonsPlugin.h>)
#import <google_mlkit_commons/GoogleMlKitCommonsPlugin.h>
#else
@import google_mlkit_commons;
#endif

#if __has_include(<google_mlkit_entity_extraction/GoogleMlKitEntityExtractionPlugin.h>)
#import <google_mlkit_entity_extraction/GoogleMlKitEntityExtractionPlugin.h>
#else
@import google_mlkit_entity_extraction;
#endif

#if __has_include(<local_auth_darwin/LocalAuthPlugin.h>)
#import <local_auth_darwin/LocalAuthPlugin.h>
#else
@import local_auth_darwin;
#endif

@implementation GeneratedPluginRegistrant

+ (void)registerWithRegistry:(NSObject<FlutterPluginRegistry>*)registry {
  [FlutterSecureStorageDarwinPlugin registerWithRegistrar:[registry registrarForPlugin:@"FlutterSecureStorageDarwinPlugin"]];
  [GoogleMlKitCommonsPlugin registerWithRegistrar:[registry registrarForPlugin:@"GoogleMlKitCommonsPlugin"]];
  [GoogleMlKitEntityExtractionPlugin registerWithRegistrar:[registry registrarForPlugin:@"GoogleMlKitEntityExtractionPlugin"]];
  [LocalAuthPlugin registerWithRegistrar:[registry registrarForPlugin:@"LocalAuthPlugin"]];
}

@end
