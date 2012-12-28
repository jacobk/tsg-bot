# README

## Saker man måste ha

### Pre-reqs

1. Github konto + [git client](http://git-scm.com/), eller [github för windows](http://windows.github.com/) eller [github för mac](http://mac.github.com/).
2. [Heroku konto + Heroku toolbelt](https://devcenter.heroku.com/articles/quickstart)
3. Tillagd som collaborator på heroku-appen och på detta repot

### Komma igång

* Klona repot
 
```shell
$ cd <parent dir>
$ git clone git@github.com:jacobk/tsg-bot.git
```

* Konfa så det går att deploya till Heroku

```shell
$ git remote add heroku git@heroku.com:tsg.git
```

## Lägga till script

**1a. (Lägga till ett "officielt" script)**
  * Hitta ett script i http://hubot-script-catalog.herokuapp.com/ (*eller direkt från https://github.com/github/hubot-scripts*)
  * Uppdatera `hubot-scripts.json` med namnet på scriptet.
  * Spara filen.

**1b. (Lägga till ett custom script)**
  * Spara scriptet (med .coffee ändelsen) i `scripts` katalogen. Se till att filen har ett unikt namn, även bland de som är med i `hubot-scripts.json`.

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

## Köra lokalt

För att kunna köra boten lokalt på datorn behövs [node.js](http://nodejs.org/) och [npm](https://npmjs.org/).

Mer info finns på [hubot projektet](https://github.com/github/hubot#getting-your-own). Följer man instruktionerna under [Testing locally](Testing hubot locally) startar boten i ett interactiv shell (som i bash) där man kan testa scripten utan att behöva koppla upp den mot IRC osv.
