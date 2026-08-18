# Eigene Bilder für Modell-Symbole

Bilder hier ablegen — LibreChat liefert sie unter `/images/custom/<datei>` aus.
In `librechat/librechat.yaml` dann so verwenden:

```yaml
iconURL: "/images/custom/gemma-color.png"
```

Quadratisches PNG oder SVG ab etwa 128×128 sieht am besten aus.
Nach dem Hinzufügen genügt ein Neuladen der Seite; nur bei Änderungen an
der YAML ist ein Neustart nötig:

```bash
docker compose -f docker-compose.rocm.yml restart librechat
```
