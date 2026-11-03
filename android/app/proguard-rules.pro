
-keep class com.follow.clash.models.** { *; }

-keep class com.follow.clash.service.models.** { *; }

# snakeyaml references java.beans (absent on Android); we only load/dump Map via SafeConstructor
-dontwarn java.beans.**
-keep class com.follow.clash.root.RootProxyMain { public static void main(java.lang.String[]); }
