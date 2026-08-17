# Modelle verwalten

Modelle laden, entladen und bei LiteLLM registrieren.

[← Zur Übersicht](../../README.md) &nbsp;|&nbsp; [English version](../en/models.md)

**Dokumentation:** [Installation & Erste Schritte](installation.md) · [Architektur & Dienste](architektur.md) · [Werkzeuge fürs LLM (MCP)](werkzeuge.md) · [LibreChat (zweite Oberfläche)](librechat.md) · [Code-Sandbox](code-sandbox.md) · [Android-Entwicklung](android.md) · [Wissensdatenbank (Vault)](wissensdatenbank.md) · **Modelle verwalten** · [Betrieb & Wartung](betrieb.md) · [Sicherheit & Fernzugriff](sicherheit.md) · [Weitere Stacks](weitere-stacks.md)

---

## Modelle bei LiteLLM eintragen

Neue Modelle werden **automatisch** bei LiteLLM registriert — egal ob du sie über die [Dashboard-Modellverwaltung](architektur.md#dashboard) lädst oder direkt per `docker exec ollama ollama pull …`. Das Dashboard gleicht dafür im Hintergrund alle ~60 Sekunden ab, welche installierten Ollama-Modelle LiteLLM noch nicht kennt, trägt sie unter `ollama/<modell>` ein (idempotent — bereits vorhandene werden übersprungen) und stößt nach einem über die Dashboard-Oberfläche gestarteten Download zusätzlich sofort einen Abgleich an, statt auf das nächste Intervall zu warten. Der Status („✓ Automatisch mit LiteLLM synchronisiert …") steht im „Modelle laden"-Popup des Dashboards.

Das setzt voraus, dass `LITELLM_MASTER_KEY` beim Dashboard-Container ankommt (macht `install.sh`/die `.env` automatisch); ohne Key zeigt das Popup „⚠ Automatische LiteLLM-Registrierung inaktiv" und du registrierst manuell:

```bash
docker exec ollama ollama pull qwen2.5:14b
./scripts/sync-ollama-models.sh
```

Das Skript bleibt als manueller Fallback erhalten (z. B. für sofortige Kontrolle statt bis zu 60 s zu warten) und ist ebenfalls **idempotent**.
