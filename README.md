# Turning the knobs

**1a. (Lägga till ett "officielt" script)**
  * Hitta ett script i http://hubot-script-catalog.herokuapp.com/ (*eller direkt från https://github.com/github/hubot-scripts*)
  * Uppdatera `hubot-scripts.json` med namnet på scriptet.
  * Spara filen.

**1b. (Lägga till ett custom script)**
  * Spara scriptet (med .coffee ändelsen) i `scripts` katalogen. (*se till att filen har ett unikt namn, även bland de som är med i `hubot-scripts.json`.

**2. Spara & Deploya**
  * Comitta alla ändringar du gjort.
  
```shell
$ git add .
$ git commit -m "I added the awsome fluffer script"
```

  * Deploya till Heroku

```shell
$ git push heroku master
```

  * Vänta och se att allt verkar funka och botten kommer tillbaks till kanalen (boten kommer startas om)
  * Merga dina ändringarna med github

```shell
$ git pull --rebase origin master # Behövs bara om nån annan ändrat nått
$ git push origin master
```
