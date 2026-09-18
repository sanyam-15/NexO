package com.chere3.nexo

/**
 * Minimal native port of the Dart [CaptureParser] amount/card logic, used only
 * to compose the confirm notification ("{app} por ${cantidad}") in real time
 * from the listener. The authoritative parse still happens in Dart when the app
 * materializes the movement; this mirrors the same rules so the figure the user
 * approves matches what gets registered.
 */
object CaptureParser {

    private val symbolMoney = Regex("(?:\\$|mxn|mx\\$)\\s*([0-9][0-9.,]*[0-9]|[0-9])", RegexOption.IGNORE_CASE)
    private val suffixMoney = Regex("([0-9][0-9.,]*[0-9]|[0-9])\\s*(?:pesos|mxn|mn)\\b", RegexOption.IGNORE_CASE)
    private val bareMoney = Regex("(?<![0-9.,])(\\d{1,3}(?:,\\d{3})+(?:\\.\\d{2})?|\\d+\\.\\d{2})(?![0-9])")

    private val cardLast4 = Regex(
        "(?:termina(?:ci[oó]n|da)?\\s*(?:en)?|final(?:iza)?\\s*(?:en)?|\\*{2,}\\s*|x{2,}\\s*|\\.{2,}\\s*)\\s*(\\d{4})\\b",
        RegexOption.IGNORE_CASE
    )

    // Verbs that signal a real money movement (vs. a balance/marketing alert).
    private val directionVerbs = listOf(
        "compra", "cargo", "pago", "pagaste", "gastaste", "retiro", "retiraste",
        "deposito", "depositaron", "abono", "recibiste", "recibido", "recibida",
        "transferencia", "spei", "devolucion", "reembolso", "domiciliacion", "disposicion"
    )

    private val incomeWords = listOf(
        "deposito", "depositaron", "te depositaron", "abono", "recibiste", "recibio",
        "recibido", "recibida", "transferencia recibida", "spei recibido", "pago recibido",
        "devolucion", "reembolso", "te enviaron", "nomina", "ingreso"
    )
    private val strongExpenseWords = listOf(
        "compra", "cargo", "pagaste", "gastaste", "retiro", "retiraste", "disposicion",
        "dispusiste", "debito", "enviaste", "transferencia enviada", "spei enviado", "domiciliacion"
    )

    fun parseAmount(raw: String): Double? {
        val lower = raw.lowercase()
        val candidates = ArrayList<Pair<Int, String>>()
        for (m in symbolMoney.findAll(raw)) candidates.add(m.range.first to m.groupValues[1])
        for (m in suffixMoney.findAll(raw)) candidates.add(m.range.first to m.groupValues[1])
        if (candidates.isEmpty()) {
            for (m in bareMoney.findAll(raw)) candidates.add(m.range.first to m.groupValues[1])
        }
        if (candidates.isEmpty()) return null

        fun isBalance(idx: Int): Boolean {
            val from = (idx - 40).coerceIn(0, lower.length)
            val ctx = lower.substring(from, idx.coerceIn(0, lower.length))
            return ctx.contains("saldo") || ctx.contains("disponible")
        }

        val nonBalance = candidates.filter { !isBalance(it.first) }.sortedBy { it.first }
        for (c in nonBalance) {
            val v = normalizeAmount(c.second)
            if (v != null) return v
        }
        return null
    }

    private fun normalizeAmount(s: String): Double? {
        var t = s.trim().replace(Regex("[^0-9.,]"), "")
        t = t.replace(Regex("[.,]+$"), "")
        if (t.isEmpty()) return null

        val lastDot = t.lastIndexOf('.')
        val lastComma = t.lastIndexOf(',')
        if (lastDot >= 0 && lastComma >= 0) {
            t = if (lastComma > lastDot) t.replace(".", "").replace(",", ".") else t.replace(",", "")
        } else if (lastComma >= 0) {
            val parts = t.split(",")
            t = if (parts.size == 2 && parts.last().length == 2) "${parts.first()}.${parts.last()}"
            else t.replace(",", "")
        } else if (lastDot >= 0) {
            val parts = t.split(".")
            if (parts.size > 2) t = t.replace(".", "")
            else if (parts.size == 2 && parts.last().length == 3) t = t.replace(".", "")
        }
        val v = t.toDoubleOrNull()
        return if (v == null || v <= 0) null else v
    }

    fun parseCardLast4(raw: String): String? = cardLast4.find(raw)?.groupValues?.getOrNull(1)

    fun hasDirectionVerb(raw: String): Boolean {
        val norm = normalize(raw)
        return directionVerbs.any { norm.contains(it) }
    }

    /** True when the text has a currency-anchored amount ($ / MXN / "pesos"), not a bare number. */
    private fun hasAnchoredAmount(raw: String): Boolean =
        symbolMoney.containsMatchIn(raw) || suffixMoney.containsMatchIn(raw)

    /**
     * Strong financial signal for DISCOVERY of unknown apps: a currency-anchored
     * amount AND a movement verb. Stricter than [isRecognized] so a chat message
     * that merely contains a bare number + a word doesn't get captured.
     */
    fun looksFinancial(raw: String): Boolean = hasAnchoredAmount(raw) && hasDirectionVerb(raw)

    /** A movement is "recognized" (high confidence) when it has both an amount and a verb. */
    fun isRecognized(raw: String): Boolean = parseAmount(raw) != null && hasDirectionVerb(raw)

    /** Deterministic direction ("income"/"expense"), mirroring the Dart parser. */
    fun parseDirection(raw: String): String {
        val norm = normalize(raw)
        val inc = firstHit(norm, incomeWords)
        val exp = firstHit(norm, strongExpenseWords)
        if (inc != null && exp != null) return if (inc <= exp) "income" else "expense"
        if (inc != null) return "income"
        return "expense" // strong expense, a bare "pago", or unknown → expense
    }

    private fun firstHit(haystack: String, needles: List<String>): Int? {
        var best: Int? = null
        for (n in needles) {
            val i = haystack.indexOf(n)
            if (i >= 0 && (best == null || i < best!!)) best = i
        }
        return best
    }

    private fun normalize(s: String): String {
        var out = s.lowercase()
        val map = mapOf('á' to 'a', 'é' to 'e', 'í' to 'i', 'ó' to 'o', 'ú' to 'u', 'ü' to 'u', 'ñ' to 'n')
        for ((k, v) in map) out = out.replace(k, v)
        return out
    }
}
