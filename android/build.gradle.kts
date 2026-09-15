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

// file_picker 8.x 的 Android 模块仍以 android-34 编译，而它依赖的
// flutter_plugin_android_lifecycle 要求 consumer 至少用 android-36 编译，
// 会让 :file_picker:checkDebugAarMetadata 失败。
// 这里把所有模块的 compileSdk 统一抬到 36（与 app 模块一致），
// 已是 36 的模块不受影响。
subprojects {
    // 上面的 evaluationDependsOn(":app") 已经把 :app 求值完了，
    // 这种情况不能再注册 afterEvaluate（它本来也已是 36），跳过。
    if (!state.executed) {
        afterEvaluate {
            val androidExt = extensions.findByName("android") ?: return@afterEvaluate
            val methods = androidExt.javaClass.methods
            val setter = methods.firstOrNull { it.name == "setCompileSdk" && it.parameterTypes.size == 1 }
                ?: methods.firstOrNull {
                    it.name == "compileSdkVersion" &&
                        it.parameterTypes.size == 1 &&
                        it.parameterTypes[0] == Int::class.javaPrimitiveType
                }
            setter?.invoke(androidExt, 36)
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
