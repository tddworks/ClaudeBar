package com.tddworks.claudebar.datasources.lookup

// The JVM runs tests only (MODULAR_DESIGN §9).
internal actual fun loginUserName(): String = System.getProperty("user.name") ?: ""
