# README

## Saker man måste ha

### Pre-reqs

#### Utvecklingsmiljö

1. Githubkonto + [git client](http://git-scm.com/), eller [github för windows](http://windows.github.com/) eller [github för mac](http://mac.github.com/).


#### Deployment

1. [Heroku konto + Heroku toolbelt](https://devcenter.heroku.com/articles/quickstart)
3. Tillagd som collaborator på heroku-appen och på detta repot

### Komma igång

* Installera node.js och npm
* Klona repot
 
```shell
$ cd <parent dir>
$ git clone git@github.com:jacobk/tsg-bot.git
```

* Installera lokalt (installerar inget utanför den utcheckade mappen)

```shell
$ cd tsg-bot
$ npm install    # Körs även automatiskt om man försöker starta boten
```

* Starta boten. Den startas med Shell-adaptern direkt i terminalen så man kan prata med den utan att klydda med IRC osv.

```shell
$ bin/hubot
```

* Konfigurera botten (om det behövs). Boten konfas via environment variabler.

```shell
$ export PORT=8080 # Default port, ändra om du kör nått annat på 8080
$ export HUBOT_LOG_LEVEL=info # Ändra till debug om du vill se mer logging
```

#### ~~Skapa en parse brain~~

*NB. Parse används inte längre. Använder redis to go gratis-instans som temporär lösning*

<del>
Det görs lättast med curl. Men fiddler osv. funkar också.

Credentials till vårt Parse.com konto hittas i [detta google doc](https://docs.google.com/document/d/1QNyat-n3vl6ulFGGfRMAH3o7v9F7pB8AQFdq4roUvXk/edit)

Det går att inspektera Parse.com-datan i [data browsern](https://parse.com/apps/tsg--2/collections#class/brains/p0).
</del>
```shell
$ curl -X POST \
    -H "X-Parse-Application-Id: <LOGGA IN O KOLLA PÅ PARSE.COM>" \
    -H "X-Parse-REST-API-Key: <LOGGA IN O KOLLA PÅ PARSE.COM>" \
    -H "Content-Type: application/json" \
    -d '{"tester": "<ÄNDRA TILL DITT NICK<"}' \
    https://api.parse.com/1/classes/brains
```




### Komma igång med deployment


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
