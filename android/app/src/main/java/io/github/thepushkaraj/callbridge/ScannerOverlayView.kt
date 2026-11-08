package io.github.thepushkaraj.callbridge

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.RectF
import android.util.AttributeSet
import android.view.View

/**
 * Dims the camera preview outside a centered rounded window and draws four
 * white corner brackets around it. Pure presentation; hit-testing is not used.
 */
class ScannerOverlayView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0
) : View(context, attrs, defStyleAttr) {

    private val density = resources.displayMetrics.density

    private val dimPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = 0x8A000000.toInt()
    }
    private val clearPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        xfermode = PorterDuffXfermode(PorterDuff.Mode.CLEAR)
    }
    private val bracketPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 4f * density
        strokeCap = Paint.Cap.ROUND
        color = 0xF2FFFFFF.toInt()
    }

    private val boxSize = 262f * density
    private val cornerRadius = 26f * density
    private val bracketLength = 34f * density

    private val windowRect = RectF()

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        if (width == 0 || height == 0) return

        val cx = width / 2f
        val cy = height / 2f
        windowRect.set(cx - boxSize / 2f, cy - boxSize / 2f, cx + boxSize / 2f, cy + boxSize / 2f)

        // Dim everything outside the rounded window.
        val layer = canvas.saveLayer(0f, 0f, width.toFloat(), height.toFloat(), null)
        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), dimPaint)
        canvas.drawRoundRect(windowRect, cornerRadius, cornerRadius, clearPaint)
        canvas.restoreToCount(layer)

        drawBrackets(canvas)
    }

    private fun drawBrackets(canvas: Canvas) {
        val left = windowRect.left
        val top = windowRect.top
        val right = windowRect.right
        val bottom = windowRect.bottom
        val len = bracketLength

        // Top-left
        canvas.drawLine(left, top + len, left, top, bracketPaint)
        canvas.drawLine(left, top, left + len, top, bracketPaint)
        // Top-right
        canvas.drawLine(right - len, top, right, top, bracketPaint)
        canvas.drawLine(right, top, right, top + len, bracketPaint)
        // Bottom-right
        canvas.drawLine(right, bottom - len, right, bottom, bracketPaint)
        canvas.drawLine(right, bottom, right - len, bottom, bracketPaint)
        // Bottom-left
        canvas.drawLine(left + len, bottom, left, bottom, bracketPaint)
        canvas.drawLine(left, bottom, left, bottom - len, bracketPaint)
    }
}
