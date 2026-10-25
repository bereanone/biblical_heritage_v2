plugins { id("com.android.asset-pack") }
assetPack {
    packName.set("bible_audio_1")
    dynamicDelivery { deliveryType.set("install-time") }
}
// Generated files are staged after Flutter compilation, before pack processing.
tasks.configureEach {
    if (name != "clean") dependsOn(":app:stagePlayAssets")
}
