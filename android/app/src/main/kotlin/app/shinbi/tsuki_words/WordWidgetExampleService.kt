package app.shinbi.tsuki_words

import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews
import android.widget.RemoteViewsService

/**
 * Supplies the bounded, device-protected example preview to the widget.
 *
 * A collection view shows every stored example and remains scrollable when the
 * complete text is taller than the available widget area; RemoteViews does not
 * permit an arbitrary ScrollView hierarchy.
 */
class WordWidgetExampleService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
        ExampleFactory(
            applicationContext,
            intent.getStringExtra(EXTRA_WORD_ID).orEmpty(),
        )

    private class ExampleFactory(
        private val context: Context,
        private val wordId: String,
    ) : RemoteViewsFactory {
        private var rows: List<ExampleRow> = emptyList()

        override fun onCreate() {
            reload()
        }

        override fun onDataSetChanged() {
            reload()
        }

        override fun onDestroy() {
            rows = emptyList()
        }

        override fun getCount(): Int = rows.size.coerceAtLeast(1)

        override fun getViewAt(position: Int): RemoteViews? {
            if (position !in 0 until getCount()) return null
            val current = rows.getOrNull(position) ?: ExampleRow(
                japanese = "",
                korean = context.getString(R.string.word_widget_example_unavailable),
            )
            return RemoteViews(context.packageName, R.layout.word_widget_example_row).apply {
                setTextViewText(
                    R.id.widget_example_number,
                    context.getString(R.string.word_widget_example_number, position + 1),
                )
                setViewVisibility(
                    R.id.widget_example_number,
                    if (rows.isEmpty()) View.GONE else View.VISIBLE,
                )
                setTextViewText(R.id.widget_example, current.japanese)
                setTextViewText(R.id.widget_example_meaning, current.korean)
                setViewVisibility(
                    R.id.widget_example,
                    if (current.japanese.isBlank()) View.GONE else View.VISIBLE,
                )
                if (rows.isNotEmpty()) {
                    setOnClickFillInIntent(R.id.widget_example_row, Intent())
                }
            }
        }

        override fun getLoadingView(): RemoteViews? = null

        override fun getViewTypeCount(): Int = 1

        override fun getItemId(position: Int): Long =
            if (position in 0 until getCount()) {
                "$wordId:$position".hashCode().toLong() and UNSIGNED_INT_MASK
            } else {
                0L
            }

        override fun hasStableIds(): Boolean = true

        private fun reload() {
            val word = LiveWallpaperPreferences.readPreviewWord(context, wordId)
            rows = word?.examples.orEmpty().mapNotNull { example ->
                val korean = example.naturalTranslation.ifBlank {
                    example.literalTranslation
                }
                if (example.original.isBlank() || korean.isBlank()) {
                    null
                } else {
                    ExampleRow(japanese = example.original, korean = korean)
                }
            }

            // Older saved widget data only has the legacy single-example
            // fields. Keep that data visible until Flutter syncs the full list.
            if (rows.isEmpty()) {
                val japanese = word?.example.orEmpty()
                val korean = word?.exampleMeaning.orEmpty()
                if (japanese.isNotBlank() && korean.isNotBlank()) {
                    rows = listOf(ExampleRow(japanese = japanese, korean = korean))
                }
            }
        }
    }

    private data class ExampleRow(
        val japanese: String,
        val korean: String,
    )

    companion object {
        internal const val EXTRA_WORD_ID = "widgetWordId"
        private const val UNSIGNED_INT_MASK = 0xffff_ffffL
    }
}
