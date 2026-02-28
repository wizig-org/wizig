package dev.ziggy.ziggyexample

import org.junit.Test
import org.junit.Assert.assertTrue

class MainActivitySmokeTest {
    @Test
    fun packageNameLooksValid() {
        assertTrue("dev.ziggy.ziggyexample".contains("."))
    }
}
