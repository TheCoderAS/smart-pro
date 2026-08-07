allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Some plugin subprojects pin stale compileSdks (reactive_ble_mobile
// compiles at 33) while modern androidx artifacts require 34+. Force
// every Android subproject up to the app's compileSdk.
subprojects {
    afterEvaluate {
        extensions.findByName("android")?.let { ext ->
            val method = ext.javaClass.methods.firstOrNull {
                it.name == "setCompileSdkVersion" && it.parameterTypes.singleOrNull() == Int::class.javaPrimitiveType
            }
            method?.invoke(ext, 37)
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
