import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Project-wide disk image cache — replaces the DefaultCacheManager singleton.
///
/// DefaultCacheManager uses a 200-item / 30-day config which is generous but
/// doesn't differentiate between tiny avatar images and full-res gallery photos.
/// This config tunes:
///   • maxNrOfCacheObjects: 300 — covers all property gallery pages a user
///     realistically browses in one session without blowing disk.
///   • stalePeriod: 7 days — property photos rarely change; matches iOS
///     SDWebImage cache policy (TTL = 1 week).
///
/// Pass `cacheManager: PPCacheManager.instance` to every CachedNetworkImage
/// that uses the default manager, so cache clears from the perf dashboard
/// correctly target the same store.
class PPCacheManager extends CacheManager with ImageCacheManager {
  static const _key = 'pp_image_cache';

  static final PPCacheManager instance = PPCacheManager._();

  PPCacheManager._()
      : super(
          Config(
            _key,
            stalePeriod: const Duration(days: 7),
            maxNrOfCacheObjects: 300,
          ),
        );
}
