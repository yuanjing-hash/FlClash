import javax.inject.Inject

plugins {
    id("com.android.library")
}

android {
    namespace = "com.follow.clash.rootruntime"
    compileSdk =
        libs.versions.compileSdk
            .get()
            .toInt()
    ndkVersion = libs.versions.ndkVersion.get()
    defaultConfig {
        minSdk =
            libs.versions.minSdk
                .get()
                .toInt()
    }
    packaging.jniLibs.keepDebugSymbols.add("**/libroot_mihomo.so")
}

abstract class BuildRootTunCore : DefaultTask() {
    @get:Inject
    abstract val execOperations: ExecOperations

    @get:InputDirectory
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val sourceDirectory: DirectoryProperty

    @get:InputFile
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val script: RegularFileProperty

    @get:Input
    abstract val abis: ListProperty<String>

    @get:Input
    abstract val goVersion: Property<String>

    @get:Internal
    abstract val ndkDirectory: DirectoryProperty

    @get:OutputDirectory
    abstract val outputDirectory: DirectoryProperty

    @TaskAction
    fun build() {
        outputDirectory.get().asFile.deleteRecursively()
        abis.get().forEach { abi ->
            execOperations.exec {
                commandLine(
                    "sh",
                    script.get().asFile.path,
                    sourceDirectory.get().asFile.path,
                    outputDirectory
                        .dir(abi)
                        .get()
                        .asFile.path,
                    abi,
                    ndkDirectory.get().asFile.path,
                )
            }
        }
    }
}

androidComponents {
    val components = this
    val platforms = providers.gradleProperty("target-platform").orNull?.split(",")
    val rootAbis =
        listOfNotNull(
            "arm64-v8a".takeIf { platforms == null || "android-arm64" in platforms },
            "x86_64".takeIf { platforms == null || "android-x64" in platforms },
        ).also { require(it.isNotEmpty()) { "Root TUN requires a 64-bit Flutter target" } }
    val buildRootTunCore =
        tasks.register<BuildRootTunCore>("buildRootTunCore") {
            sourceDirectory.set(rootProject.layout.projectDirectory.dir("../core/Clash.Meta"))
            script.set(rootProject.layout.projectDirectory.file("root-tun/build-core.sh"))
            abis.set(rootAbis)
            goVersion.set(providers.exec { commandLine("go", "env", "GOVERSION") }.standardOutput.asText)
            ndkDirectory.set(components.sdkComponents.ndkDirectory)
            outputDirectory.set(layout.buildDirectory.dir("generated/rootTunJni"))
        }
    onVariants { variant ->
        variant.sources.jniLibs?.addGeneratedSourceDirectory(buildRootTunCore, BuildRootTunCore::outputDirectory)
    }
}
