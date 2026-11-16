package io.github.thepushkaraj.callbridge

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.view.View
import android.view.Window
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.camera.core.Camera
import androidx.camera.core.CameraSelector
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage
import java.util.concurrent.Executors

/**
 * Full-screen QR scanner. Recognizes the pairing payload shown by the Mac app
 * and returns it to [MainActivity]; anything else shows an inline hint and
 * keeps scanning.
 */
class ScannerActivity : AppCompatActivity() {

    private lateinit var previewView: PreviewView
    private lateinit var errorText: TextView
    private lateinit var torchIcon: ImageView

    private var camera: Camera? = null
    private var torchOn = false
    private var finished = false
    private var lastErrorAt = 0L

    private val analysisExecutor = Executors.newSingleThreadExecutor()
    private val scanner by lazy {
        BarcodeScanning.getClient(
            BarcodeScannerOptions.Builder()
                .setBarcodeFormats(Barcode.FORMAT_QR_CODE)
                .build()
        )
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_scanner)
        makeSystemBarsTransparent()

        previewView = findViewById(R.id.preview_view)
        errorText = findViewById(R.id.scanner_error)
        torchIcon = findViewById(R.id.torch_icon)

        findViewById<FrameLayout>(R.id.close_button).setOnClickListener { finish() }
        findViewById<FrameLayout>(R.id.torch_button).setOnClickListener { toggleTorch() }

        if (checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
            startCamera()
        } else {
            requestPermissions(arrayOf(Manifest.permission.CAMERA), CAMERA_PERMISSION_REQUEST)
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != CAMERA_PERMISSION_REQUEST) return
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            startCamera()
        } else {
            errorText.text = getString(R.string.scanner_camera_needed)
            errorText.visibility = View.VISIBLE
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        analysisExecutor.shutdown()
        scanner.close()
    }

    private fun makeSystemBarsTransparent() {
        window.statusBarColor = Color.TRANSPARENT
        window.navigationBarColor = Color.TRANSPARENT
        if (Build.VERSION.SDK_INT >= 28) {
            window.attributes.layoutInDisplayCutoutMode =
                android.view.WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }
        @Suppress("DEPRECATION")
        window.decorView.systemUiVisibility =
            View.SYSTEM_UI_FLAG_LAYOUT_STABLE or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
    }

    private fun startCamera() {
        val providerFuture = ProcessCameraProvider.getInstance(this)
        providerFuture.addListener({
            val provider = providerFuture.get()
            val preview = Preview.Builder().build().also {
                it.setSurfaceProvider(previewView.surfaceProvider)
            }
            val analysis = ImageAnalysis.Builder()
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .build()
                .also { it.setAnalyzer(analysisExecutor, ::analyze) }

            provider.unbindAll()
            camera = provider.bindToLifecycle(this, CameraSelector.DEFAULT_BACK_CAMERA, preview, analysis)
        }, ContextCompat.getMainExecutor(this))
    }

    @ExperimentalGetImage
    private fun analyze(proxy: ImageProxy) {
        if (finished) {
            proxy.close()
            return
        }
        val mediaImage = proxy.image
        if (mediaImage == null) {
            proxy.close()
            return
        }
        val input = InputImage.fromMediaImage(mediaImage, proxy.imageInfo.rotationDegrees)
        scanner.process(input)
            .addOnSuccessListener { barcodes ->
                if (finished) return@addOnSuccessListener
                for (barcode in barcodes) {
                    val raw = barcode.rawValue ?: continue
                    if (handlePayload(raw)) break
                }
            }
            .addOnCompleteListener { proxy.close() }
    }

    /** Returns true when the payload was accepted and the activity is finishing. */
    private fun handlePayload(raw: String): Boolean {
        when (val decoded = PairingPayload.decode(raw)) {
            is PairingPayload.DecodeResult.Ok -> {
                val payload = decoded.payload
                finished = true
                getSharedPreferences(PREFS, MODE_PRIVATE)
                    .edit()
                    .putString("host", payload.host)
                    .putString("port", payload.port.toString())
                    .putString("secret", payload.secret ?: "")
                    .apply()

                val result = Intent()
                    .putExtra(EXTRA_HOST, payload.host)
                    .putExtra(EXTRA_PORT, payload.port)
                runOnUiThread {
                    setResult(Activity.RESULT_OK, result)
                    finish()
                }
                return true
            }
            PairingPayload.DecodeResult.NotOnLocalNetwork -> {
                showScanError(getString(R.string.scanner_error_lan))
                return false
            }
            PairingPayload.DecodeResult.Invalid -> {
                showScanError(getString(R.string.scanner_error))
                return false
            }
        }
    }

    private fun showScanError(message: String) {
        val now = System.currentTimeMillis()
        if (now - lastErrorAt < ERROR_DEBOUNCE_MS) return
        lastErrorAt = now
        runOnUiThread {
            errorText.text = message
            errorText.visibility = View.VISIBLE
            errorText.animate().cancel()
            errorText.alpha = 1f
            errorText.postDelayed({
                errorText.animate().alpha(0f).withEndAction {
                    errorText.visibility = View.GONE
                }.setDuration(250).start()
            }, ERROR_VISIBLE_MS)
        }
    }

    private fun toggleTorch() {
        val cam = camera ?: return
        torchOn = !torchOn
        cam.cameraControl.enableTorch(torchOn)
        torchIcon.alpha = if (torchOn) 1f else 0.55f
    }

    companion object {
        const val EXTRA_HOST = "host"
        const val EXTRA_PORT = "port"
        private const val PREFS = "callbridge"
        private const val CAMERA_PERMISSION_REQUEST = 10
        private const val ERROR_VISIBLE_MS = 1800L
        private const val ERROR_DEBOUNCE_MS = 1500L
    }
}
