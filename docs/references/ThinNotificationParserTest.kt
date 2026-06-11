package io.split.client.thin.internal.streaming

import org.junit.Assert.*
import org.junit.Test

class ThinNotificationParserTest {

    private val parser = ThinNotificationParser()

    @Test
    fun `parseRaw extracts channel, data, and timestamp from valid JSON`() {
        val json = """{"channel":"test-channel","data":"test-data","timestamp":1234567890}"""

        val result = parser.parseRaw(json)

        assertNotNull(result)
        assertEquals("test-channel", result?.channel)
        assertEquals("test-data", result?.data)
        assertEquals(1234567890L, result?.timestamp)
    }

    @Test
    fun `parseRaw returns null for malformed JSON`() {
        val result = parser.parseRaw("not valid json {")

        assertNull(result)
    }

    @Test
    fun `parse returns EvaluationUpdateNotification for valid EVALUATION_UPDATE`() {
        val raw = RawThinNotification(
            channel = "evaluations-channel",
            data = """{"type":"EVALUATIONS_UPDATE","changeNumber":42}""",
            timestamp = 9876543210L
        )

        val result = parser.parse(raw)

        assertNotNull(result)
        assertTrue(result is EvaluationUpdateNotification)
        val notification = result as EvaluationUpdateNotification
        assertEquals(42L, notification.changeNumber)
        assertEquals("evaluations-channel", notification.channel)
        assertEquals(9876543210L, notification.timestamp)
        assertEquals(ThinNotificationType.EVALUATION_UPDATE, notification.type)
    }

    @Test
    fun `parse returns null for EVALUATION_UPDATE with missing changeNumber`() {
        val raw = RawThinNotification(
            channel = "test",
            data = """{"type":"EVALUATIONS_UPDATE"}""",
            timestamp = 1000L
        )

        val result = parser.parse(raw)

        assertNull(result)
    }

    @Test
    fun `parse returns ThinControlNotification for STREAMING_RESUMED`() {
        val raw = RawThinNotification(
            channel = "control-channel",
            data = """{"type":"CONTROL","controlType":"STREAMING_RESUMED"}""",
            timestamp = 5000L
        )

        val result = parser.parse(raw)

        assertNotNull(result)
        assertTrue(result is ThinControlNotification)
        val notification = result as ThinControlNotification
        assertEquals(ThinControlNotification.ControlType.STREAMING_RESUMED, notification.controlType)
        assertEquals("control-channel", notification.channel)
        assertEquals(5000L, notification.timestamp)
        assertEquals(ThinNotificationType.CONTROL, notification.type)
    }

    @Test
    fun `parse returns ThinControlNotification for STREAMING_DISABLED`() {
        val raw = RawThinNotification(
            channel = "control",
            data = """{"type":"CONTROL","controlType":"STREAMING_DISABLED"}""",
            timestamp = 6000L
        )

        val result = parser.parse(raw)

        assertTrue(result is ThinControlNotification)
        assertEquals(ThinControlNotification.ControlType.STREAMING_DISABLED, (result as ThinControlNotification).controlType)
    }

    @Test
    fun `parse returns ThinControlNotification for STREAMING_PAUSED`() {
        val raw = RawThinNotification(
            channel = "control",
            data = """{"type":"CONTROL","controlType":"STREAMING_PAUSED"}""",
            timestamp = 7000L
        )

        val result = parser.parse(raw)

        assertTrue(result is ThinControlNotification)
        assertEquals(ThinControlNotification.ControlType.STREAMING_PAUSED, (result as ThinControlNotification).controlType)
    }

    @Test
    fun `parse returns ThinControlNotification for STREAMING_RESET`() {
        val raw = RawThinNotification(
            channel = "control",
            data = """{"type":"CONTROL","controlType":"STREAMING_RESET"}""",
            timestamp = 8000L
        )

        val result = parser.parse(raw)

        assertTrue(result is ThinControlNotification)
        assertEquals(ThinControlNotification.ControlType.STREAMING_RESET, (result as ThinControlNotification).controlType)
    }

    @Test
    fun `parse returns null for CONTROL with missing controlType`() {
        val raw = RawThinNotification(
            channel = "control",
            data = """{"type":"CONTROL"}""",
            timestamp = 1000L
        )

        val result = parser.parse(raw)

        assertNull(result)
    }

    @Test
    fun `parse returns null for CONTROL with invalid controlType`() {
        val raw = RawThinNotification(
            channel = "control",
            data = """{"type":"CONTROL","controlType":"INVALID_TYPE"}""",
            timestamp = 1000L
        )

        val result = parser.parse(raw)

        assertNull(result)
    }

    @Test
    fun `parse returns ThinOccupancyNotification for valid OCCUPANCY`() {
        val raw = RawThinNotification(
            channel = "occupancy-channel",
            data = """{"metrics":{"publishers":3}}""",
            timestamp = 3000L
        )

        val result = parser.parse(raw)

        assertNotNull(result)
        assertTrue(result is ThinOccupancyNotification)
        val notification = result as ThinOccupancyNotification
        assertEquals(3, notification.publishers)
        assertEquals("occupancy-channel", notification.channel)
        assertEquals(3000L, notification.timestamp)
        assertEquals(ThinNotificationType.OCCUPANCY, notification.type)
    }

    @Test
    fun `parse returns ThinOccupancyNotification for OCCUPANCY with zero publishers`() {
        val raw = RawThinNotification(
            channel = "occupancy",
            data = """{"metrics":{"publishers":0}}""",
            timestamp = 4000L
        )

        val result = parser.parse(raw)

        assertTrue(result is ThinOccupancyNotification)
        assertEquals(0, (result as ThinOccupancyNotification).publishers)
    }

    @Test
    fun `parse returns null for OCCUPANCY with missing publishers`() {
        val raw = RawThinNotification(
            channel = "occupancy",
            data = """{"type":"OCCUPANCY"}""",
            timestamp = 1000L
        )

        val result = parser.parse(raw)

        assertNull(result)
    }

    @Test
    fun `parse returns ThinStreamingError for valid ERROR`() {
        val raw = RawThinNotification(
            channel = null,
            data = """{"type":"ERROR","message":"Connection failed","code":500,"statusCode":503}""",
            timestamp = 2000L
        )

        val result = parser.parse(raw)

        assertNotNull(result)
        assertTrue(result is ThinStreamingError)
        val error = result as ThinStreamingError
        assertEquals("Connection failed", error.message)
        assertEquals(500, error.code)
        assertEquals(503, error.statusCode)
        assertEquals(2000L, error.timestamp)
        assertEquals(ThinNotificationType.ERROR, error.type)
    }

    @Test
    fun `parse returns ThinStreamingError for ERROR without statusCode`() {
        val raw = RawThinNotification(
            channel = null,
            data = """{"type":"ERROR","message":"Timeout","code":408}""",
            timestamp = 1500L
        )

        val result = parser.parse(raw)

        assertTrue(result is ThinStreamingError)
        val error = result as ThinStreamingError
        assertEquals("Timeout", error.message)
        assertEquals(408, error.code)
        assertNull(error.statusCode)
    }

    @Test
    fun `parse returns ThinStreamingError with default values for ERROR with missing fields`() {
        val raw = RawThinNotification(
            channel = null,
            data = """{"type":"ERROR"}""",
            timestamp = 1000L
        )

        val result = parser.parse(raw)

        assertTrue(result is ThinStreamingError)
        val error = result as ThinStreamingError
        assertEquals("Unknown error", error.message)
        assertEquals(-1, error.code)
        assertNull(error.statusCode)
    }

    @Test
    fun `parse returns null for unknown notification type - does not fall through to occupancy`() {
        val raw = RawThinNotification(
            channel = "test",
            data = """{"type":"UNKNOWN_TYPE"}""",
            timestamp = 1000L
        )

        val result = parser.parse(raw)

        // Unknown type must return null, not silently parse as occupancy
        assertNull(result)
    }

    @Test
    fun `parse routes to occupancy when type field is absent`() {
        val raw = RawThinNotification(
            channel = "occupancy-channel",
            data = """{"metrics":{"publishers":2}}""",
            timestamp = 3000L
        )

        val result = parser.parse(raw)

        // No "type" field → occupancy path
        assertTrue(result is ThinOccupancyNotification)
        assertEquals(2, (result as ThinOccupancyNotification).publishers)
    }

    @Test
    fun `parse returns null for malformed data JSON`() {
        val raw = RawThinNotification(
            channel = "test",
            data = "not valid json",
            timestamp = 1000L
        )

        val result = parser.parse(raw)

        assertNull(result)
    }

    @Test
    fun `parse returns EvaluationUpdateNotification with sync delay fields when present`() {
        val raw = RawThinNotification(
            channel = "evaluations-channel",
            data = """{"type":"EVALUATIONS_UPDATE","changeNumber":99,"i":60000,"s":42,"h":1}""",
            timestamp = 1000L
        )

        val result = parser.parse(raw)

        assertTrue(result is EvaluationUpdateNotification)
        val notification = result as EvaluationUpdateNotification
        assertEquals(99L, notification.changeNumber)
        assertEquals(60000L, notification.updateIntervalMs)
        assertEquals(42, notification.algorithmSeed)
        assertEquals(1, notification.hashingAlgorithm)
    }

    @Test
    fun `parse returns EvaluationUpdateNotification with null sync delay fields when absent`() {
        val raw = RawThinNotification(
            channel = "evaluations-channel",
            data = """{"type":"EVALUATIONS_UPDATE","changeNumber":10}""",
            timestamp = 1000L
        )

        val result = parser.parse(raw)

        assertTrue(result is EvaluationUpdateNotification)
        val notification = result as EvaluationUpdateNotification
        assertNull(notification.updateIntervalMs)
        assertNull(notification.algorithmSeed)
        assertNull(notification.hashingAlgorithm)
    }

    @Test
    fun `parse returns EvaluationUpdateNotification with hashing NONE (h=0)`() {
        val raw = RawThinNotification(
            channel = "evaluations-channel",
            data = """{"type":"EVALUATIONS_UPDATE","changeNumber":5,"i":30000,"s":0,"h":0}""",
            timestamp = 1000L
        )

        val result = parser.parse(raw)

        assertTrue(result is EvaluationUpdateNotification)
        val notification = result as EvaluationUpdateNotification
        assertEquals(30000L, notification.updateIntervalMs)
        assertEquals(0, notification.algorithmSeed)
        assertEquals(0, notification.hashingAlgorithm)
    }
}
