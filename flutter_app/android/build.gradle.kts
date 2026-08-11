allprojects {
    repositories {
        maven { setUrl("https://maven.aliyun.com/repository/google") }
        maven { setUrl("https://maven.aliyun.com/repository/central") }
        google()
        mavenCentral()
    }
}

// buildDir 重定向已撤销（2026-08-11）：
// 原配置 .dir("../../build") 把 build 目录强制迁移到 D 盘项目根，
// 但 Flutter plugin source 来自 Pub Cache（C 盘），导致 AGP 在
// GenerateTestConfig 调用 Path.relativize() 时跨 volume 抛
// IllegalArgumentException。恢复 Flutter 默认拓扑（android/build）。
//
// 强制所有子项目（包括第三方插件）使用 compileSdk 36，
// 解决 file_picker(33) 和 flutter_inappwebview_android(34) 硬编码旧版的问题。
gradle.afterProject {
    if (project != rootProject) {
        extensions.findByType<com.android.build.api.dsl.LibraryExtension>()?.let {
            it.compileSdk = 36
        }
        extensions.findByType<com.android.build.api.dsl.ApplicationExtension>()?.let {
            it.compileSdk = 36
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
