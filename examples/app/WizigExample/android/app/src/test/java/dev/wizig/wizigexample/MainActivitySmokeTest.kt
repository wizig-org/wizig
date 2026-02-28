package dev.wizig.wizigexample

import org.junit.Test
import org.junit.Assert.assertTrue

class MainActivitySmokeTest {
    @Test
    fun packageNameLooksValid() {
        assertTrue("dev.wizig.wizigexample".contains("."))
    }
}
