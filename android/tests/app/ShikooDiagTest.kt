package com.follow.clash

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import kotlin.io.path.createTempDirectory

class ShikooDiagTest {
    private val dir = createTempDirectory("diag").toFile()

    @Test
    fun `a crash is written before Android's own handler ends the process`() {
        val file = File(dir, "java-crash.txt")
        var handed: Throwable? = null
        val error = IllegalStateException("boom")

        crashHandler(file) { _, e -> handed = e }.uncaughtException(Thread.currentThread(), error)

        assertSame(error, handed)
        val text = file.readText()
        assertTrue(text.startsWith("--- "))
        assertTrue("IllegalStateException: boom" in text)
        assertTrue("ShikooDiagTest" in text)
    }

    @Test
    fun `the capped file keeps the newest lines whole`() {
        val file = File(dir, "events.txt")

        repeat(400) { appendCapped(file, "line $it\n", cap = 1000) }

        val lines = file.readLines().filter { it.isNotEmpty() }
        assertTrue(file.length() <= 1000)
        assertEquals("line 399", lines.last())
        assertTrue(lines.all { it.startsWith("line ") })
    }

    @Test
    fun `an ANR trace keeps only the main thread`() {
        val trace = """
            ----- pid 1 at 2026-10-07 -----
            "Signal Catcher" daemon prio=10 tid=2 Runnable
              at x

            "main" prio=5 tid=1 Sleeping
              at java.lang.Thread.sleep(Native method)
              at com.follow.clash.MainActivity.onCreate(MainActivity.kt:9)

            "Binder:1_1" prio=5 tid=3 Native
        """.trimIndent()

        val block = mainThreadBlock(trace.lineSequence())!!

        assertTrue(block.startsWith("\"main\""))
        assertTrue("MainActivity.kt:9" in block)
        assertTrue("Binder" !in block && "Signal" !in block)
        assertNull(mainThreadBlock("no threads".lineSequence()))
        assertEquals(8192, mainThreadBlock(("\"main\"\n" + "x".repeat(9000)).lineSequence())!!.length)
    }
}
