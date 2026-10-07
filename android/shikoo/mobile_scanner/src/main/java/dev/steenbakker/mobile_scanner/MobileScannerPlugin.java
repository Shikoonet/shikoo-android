package dev.steenbakker.mobile_scanner;

import io.flutter.embedding.engine.plugins.FlutterPlugin;

/** Stands in for mobile_scanner on Android: no camera, no ML Kit (SHIKOO_PATCHES.md). */
public final class MobileScannerPlugin implements FlutterPlugin {
    @Override
    public void onAttachedToEngine(FlutterPluginBinding binding) {}

    @Override
    public void onDetachedFromEngine(FlutterPluginBinding binding) {}
}
