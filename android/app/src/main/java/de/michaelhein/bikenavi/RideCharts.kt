package de.michaelhein.bikenavi

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.view.View
import kotlin.math.max

/** Native, scrollable ride charts. Unknown measurements remain gaps. */
class RideCharts(context: Context, private val ride: SavedRide) : View(context) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { strokeWidth = 3f; textSize = 31f }
    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        setMeasuredDimension(max(1200, MeasureSpec.getSize(widthMeasureSpec) * 3), 1000)
    }
    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        canvas.drawColor(Color.WHITE)
        val left = 90f
        val right = width - 30f
        val start = ride.samples.firstOrNull()?.time ?: ride.time
        val end = max(start + 1, ride.samples.lastOrNull()?.time ?: start + 1)
        fun x(time: Long) = left + (time - start).toFloat() / (end - start) * (right - left)
        val modes = ride.bikeSamples.filter { it.value.assistMode != null }
        modes.zipWithNext().forEach { (a, b) ->
            if (b.time - a.time > 120_000) return@forEach
            paint.color = when (a.value.assistMode) {
                0 -> Color.DKGRAY
                1 -> Color.rgb(38, 150, 85)
                2 -> Color.rgb(30, 93, 207)
                3 -> Color.MAGENTA
                4 -> Color.RED
                else -> Color.LTGRAY
            }
            paint.strokeWidth = 14f
            canvas.drawLine(x(a.time), 34f, x(b.time), 34f, paint)
        }
        fun chart(title: String, top: Float, samples: List<Pair<Long, Double?>>, color: Int) {
            paint.color = Color.DKGRAY
            paint.style = Paint.Style.FILL
            canvas.drawText(title, left, top - 12, paint)
            paint.color = Color.LTGRAY
            paint.strokeWidth = 2f
            canvas.drawLine(left, top + 220, right, top + 220, paint)
            val values = samples.mapNotNull { it.second }
            if (values.isEmpty()) {
                canvas.drawText("Keine Messwerte", left + 20, top + 130, paint)
                return
            }
            val minimum = values.minOrNull() ?: 0.0
            val maximum = max(minimum + 1, values.maxOrNull() ?: minimum + 1)
            paint.color = color
            paint.strokeWidth = 4f
            samples.zipWithNext().forEach { (a, b) ->
                if (a.second != null && b.second != null &&
                    b.first - a.first < 120_000) {
                    val ay = top + 220 - ((a.second!! - minimum) / (maximum - minimum) * 200).toFloat()
                    val by = top + 220 - ((b.second!! - minimum) / (maximum - minimum) * 200).toFloat()
                    canvas.drawLine(x(a.first), ay, x(b.first), by, paint)
                }
            }
            paint.color = Color.DKGRAY
            canvas.drawText("%.0f–%.0f".format(minimum, maximum), right - 180, top - 12, paint)
        }
        chart("Höhe (m)", 70f, ride.samples.map { it.time to it.altitude }, Color.rgb(30, 93, 207))
        chart("Fahrerleistung (W)", 390f,
            ride.bikeSamples.map { it.time to it.value.riderWatts?.toDouble() }, Color.rgb(38, 150, 85))
        chart("Motorleistung (W)", 710f,
            ride.bikeSamples.map { it.time to it.value.motorWatts?.toDouble() }, Color.rgb(169, 65, 146))
    }
}
