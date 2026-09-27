package de.michaelhein.bikenavi

import android.Manifest
import android.bluetooth.*
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import java.util.UUID

/** Read-only Bosch BLE diagnostics. No writes or motor-control commands. */
class BikeBluetooth(private val context: Context, private val onChange: () -> Unit) {
    private val adapter: BluetoothAdapter? = context.getSystemService(BluetoothManager::class.java)?.adapter
    private val handler = Handler(Looper.getMainLooper())
    private val suffix = "-eaa2-11e9-81b4-2a2ae2dbcce4"
    private val live = UUID.fromString("0000eb21$suffix")
    private val phone = listOf("00000011", "0000eb11").map { UUID.fromString("$it$suffix") }
    private val services = listOf("00000010", "00000020", "00000040", "0000eb10",
        "0000eb20", "0000eb40", "0000eb60", "0000eba0", "0000ebd0")
        .map { UUID.fromString("$it$suffix") }
    val candidates = LinkedHashMap<String, String>()
    var status = "Bike nicht verbunden"
        private set
    var measurement = BikeMeasurement()
        private set
    var lastReceived = 0L
        private set
    var onMeasurement: ((BikeMeasurement) -> Unit)? = null
    private var gatt: BluetoothGatt? = null
    private var scanning = false
    private val pendingNotifications = ArrayDeque<BluetoothGattCharacteristic>()
    private val scan = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            val name = try { result.scanRecord?.deviceName ?: result.device.name ?: "" }
                catch (_: SecurityException) { "" }
            val advertised = result.scanRecord?.serviceUuids?.map { it.uuid }.orEmpty()
            if (name.contains("smart system ebike", ignoreCase = true) ||
                advertised.any { it in services }) {
                val address = result.device.address
                candidates[address] = name.ifBlank { "Bosch Bike" }
                status = "Bike gefunden · bitte auswählen"
                onChange()
            }
        }
        override fun onScanFailed(errorCode: Int) {
            scanning = false
            status = "Suche fehlgeschlagen ($errorCode)"
            onChange()
        }
    }
    private val callback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(gatt: BluetoothGatt, statusCode: Int, newState: Int) {
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                status = "Verbunden · Dienste werden gelesen"
                if (allowed()) gatt.discoverServices()
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                status = "Bike getrennt"
                gatt.close()
                if (this@BikeBluetooth.gatt === gatt) this@BikeBluetooth.gatt = null
            }
            handler.post(onChange)
        }
        override fun onServicesDiscovered(gatt: BluetoothGatt, statusCode: Int) {
            if (statusCode != BluetoothGatt.GATT_SUCCESS || !allowed()) return
            val characteristics = gatt.services.flatMap { it.characteristics }
            val notify = characteristics.filter { it.uuid in phone || it.uuid == live }
            if (notify.isEmpty()) {
                status = "Verbunden; kein unterstützter Live-Datenkanal"
            } else {
                status = "Bike-Datenkanal gefunden"
                notify.forEach { characteristic ->
                    if (characteristic.properties and BluetoothGattCharacteristic.PROPERTY_NOTIFY != 0) {
                        pendingNotifications.addLast(characteristic)
                    }
                }
                enableNext(gatt)
            }
            handler.post(onChange)
        }
        override fun onDescriptorWrite(gatt: BluetoothGatt, descriptor: BluetoothGattDescriptor, status: Int) {
            enableNext(gatt)
        }
        override fun onCharacteristicChanged(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic,
                                             value: ByteArray) = receive(characteristic.uuid, value)
        @Deprecated("API 33 overload")
        override fun onCharacteristicChanged(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic) {
            @Suppress("DEPRECATION")
            receive(characteristic.uuid, characteristic.value ?: byteArrayOf())
        }
        override fun onCharacteristicRead(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic,
                                          value: ByteArray, status: Int) {
            if (status == BluetoothGatt.GATT_SUCCESS) receive(characteristic.uuid, value)
        }
    }
    private fun enableNext(gatt: BluetoothGatt) {
        if (!allowed()) return
        while (pendingNotifications.isNotEmpty()) {
            val characteristic = pendingNotifications.removeFirst()
            if (!gatt.setCharacteristicNotification(characteristic, true)) continue
            val descriptor = characteristic.getDescriptor(UUID.fromString(
                "00002902-0000-1000-8000-00805f9b34fb")) ?: continue
            // CCC descriptor enables notifications; it does not control the bicycle.
            val started = if (Build.VERSION.SDK_INT >= 33)
                gatt.writeDescriptor(descriptor, BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE) ==
                    BluetoothStatusCodes.SUCCESS
            else {
                @Suppress("DEPRECATION")
                descriptor.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                @Suppress("DEPRECATION")
                gatt.writeDescriptor(descriptor)
            }
            if (started) return
        }
        gatt.services.flatMap { it.characteristics }.firstOrNull { it.uuid == live &&
            it.properties and BluetoothGattCharacteristic.PROPERTY_READ != 0 }?.let {
            gatt.readCharacteristic(it)
        }
    }
    private fun receive(uuid: UUID, bytes: ByteArray) {
        if (bytes.isEmpty()) return
        try {
            val latest = if (uuid == live) BoschData.live(bytes)
                else if (uuid == phone.first()) BoschData.smartphone(bytes) else return
            measurement = measurement.copy(
                battery = latest.battery ?: measurement.battery,
                riderWatts = latest.riderWatts ?: measurement.riderWatts,
                motorWatts = latest.motorWatts ?: measurement.motorWatts,
                assistMode = latest.assistMode ?: measurement.assistMode,
                cadence = latest.cadence ?: measurement.cadence,
                speedKph = latest.speedKph ?: measurement.speedKph)
            if (latest != BikeMeasurement()) {
                lastReceived = System.currentTimeMillis()
                status = "Bike-Daten direkt über Bluetooth"
                onMeasurement?.invoke(latest)
                handler.post(onChange)
            }
        } catch (_: IllegalArgumentException) { status = "Unbekanntes Bike-Datenpaket"; handler.post(onChange) }
    }
    fun search() {
        if (!allowed()) { status = "Bluetooth-Berechtigung fehlt"; onChange(); return }
        if (adapter == null || !adapter.isEnabled) {
            status = "Bluetooth nicht verfügbar oder ausgeschaltet"; onChange(); return
        }
        candidates.clear()
        status = "Suche Bosch Bike …"
        try {
            adapter.bluetoothLeScanner?.startScan(scan)
            scanning = true
            handler.postDelayed({ stopScan() }, 45000)
        } catch (_: SecurityException) { status = "Bluetooth-Zugriff verweigert" }
        onChange()
    }
    fun connect(address: String) {
        if (!allowed()) return
        stopScan()
        gatt?.close()
        pendingNotifications.clear()
        try {
            status = "Verbinde Bike …"
            gatt = adapter?.getRemoteDevice(address)?.connectGatt(context, false, callback)
            context.getSharedPreferences("riding", Context.MODE_PRIVATE).edit()
                .putString("bikeAddress", address).apply()
        } catch (_: Exception) { status = "Bike-Verbindung fehlgeschlagen" }
        onChange()
    }
    fun stop() { stopScan(); if (allowed()) gatt?.disconnect(); gatt?.close(); gatt = null }
    private fun stopScan() {
        if (!scanning) return
        try { if (allowed()) adapter?.bluetoothLeScanner?.stopScan(scan) } catch (_: Exception) { }
        scanning = false
    }
    private fun allowed() = if (Build.VERSION.SDK_INT >= 31)
        context.checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED &&
            context.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED
    else context.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
}
