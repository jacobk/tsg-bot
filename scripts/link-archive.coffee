# Description:
#   Keep track of links
#
# Dependencies:
#   None
#
# Configuration:
#   None
#
# Commands:
#   None
#
# Author:
#   jacobk


# TODO
# * Figure out how to properly check content (hash)
#   - perhaps only usable for images
# * Make it possible to post link you know is old
# * List last links
# * List most posed links
# * Test if a link has been posted before

Crypto = require "crypto"

version = "1"

module.exports = (robot) ->

  # wait for brain to load, merging doesn't work
  robot.brain.on "loaded", ->
    robot.brain.data.links ?= {}
    unless robot.brain.data.links.version is version
      console.log "Migrating to #{version}"
      robot.brain.data.links.version = version
      robot.brain.save()

  robot.hear link.pattern, (msg) ->
    url  = link.normalize msg.match[1]
    nick = msg.message.user.name

    post = [nick, new Date().getTime().toString()]

    hash = link.md5hash url
    links = robot.brain.data.links

    posts = links[hash] ?= {url: url, posters: []}
    posts.posters.push post
    [firstNick, firstTime] = posts.posters[0]

    if firstNick and firstNick isnt nick
      msg.reply "OLD! #{firstNick} posted it #{new Date(parseInt(firstTime))}"
    robot.brain.save()

  robot.respond /links$/i, (msg) ->
    msg.send process.env.HEROKU_URL + "hubot/links"

  robot.router.get '/hubot/links', (req, res) ->
    res.setHeader 'content-type', 'text/html'
    nicks = {}
    links = for hash, link of robot.brain.data.links when hash isnt "version"
      for poster in link.posters
        nicks[poster[0]] = true
      link
    nicks = for nick, foo of nicks
      nick: nick
    res.end pageContent(JSON.stringify(links), JSON.stringify(nicks))


link =
  md5hash: (data) ->
    md5sum = Crypto.createHash('md5');
    md5sum.update(new Buffer(data))
    md5sum.digest("hex").substring(0,8)

  # http://daringfireball.net/2010/07/improved_regex_for_matching_urls
  pattern: /// \b (
      (?: https?://                  # http or https
        | www\d{0,3}[.]              # "www.", "www1.", "www2." … "www999."
        | [a-z0-9.\-]+[.][a-z]{2,4}/ # looks like domain name followed by a slash
      )
      (?: [^\s()<>]+                          # Run of non-space, non-()<>
        | \(([^\s()<>]+|(\([^\s()<>]+\)))*\)  # balanced parens, up to 2 levels
      )+
      (?: \(([^\s()<>]+|(\([^\s()<>]+\)))*\)  # balanced parens, up to 2 levels
        | [^\s`!()\[\]{};:'".,<>?«»“”‘’]      # not a space or one of these punct chars
      )
    ) ///

  # Very basic normalization for now
  normalize: (url) ->
    uriPattern = new RegExp "^(([^:/?#]+):)?(//([^/?#]*))?([^?#]*)(\\?([^#]*))?(#(.*))?"
    [_, _, scheme, _, authority, path, _, query, _, fragment] = url.match uriPattern
    unless scheme
      return @normalize "http://#{url}"
    scheme = scheme.toLowerCase()
    scheme = scheme.substr(0,4)
    authority = authority.toLowerCase()
    authorityParts = authority.split(":")
    if authorityParts[1] is "80"
      authority = authorityParts[0]
    path = "/" unless path
    query = "?#{query}" if query
    fragment = "##{fragment}" if fragment
    "#{scheme}://#{authority}#{path}#{query or ""}#{fragment or ""}"


pageContent = (links, nicks) ->
  """
<!DOCTYPE html>
    <head>
        <meta charset="utf-8">
        <title>Links!</title>
        <link href="//netdna.bootstrapcdn.com/twitter-bootstrap/2.2.2/css/bootstrap-combined.min.css" rel="stylesheet">
        <style>
          body {
            padding-top: 60px;
          }
          .label {
            margin-right: 3px;
          }
          .label:hover {
            cursor: pointer;
            opacity: 0.5;
          }
        </style>
    </head>
    <body>
        <div class="navbar navbar-fixed-top">
          <div class="navbar-inner">
            <div class="container">
              <a class="btn btn-navbar" data-toggle="collapse" data-target=".nav-collapse">
                <span class="icon-bar"></span>
                <span class="icon-bar"></span>
                <span class="icon-bar"></span>
              </a>
              <a class="brand" href="#">TSG LINKS</a>
              <div class="nav-collapse collapse">
                <ul class="nav">
                  <li class="active"><a href="#">Home</a></li>
                </ul>
              </div>
            </div>
          </div>
        </div>
        <div id="content" class="container">


        </div>
        <script src="//ajax.googleapis.com/ajax/libs/jquery/1.8.3/jquery.min.js"></script>
        <script src="//cdnjs.cloudflare.com/ajax/libs/underscore.js/1.4.3/underscore-min.js"></script>
        <script src="//cdnjs.cloudflare.com/ajax/libs/backbone.js/0.9.9/backbone-min.js"></script>
        <script src="//netdna.bootstrapcdn.com/twitter-bootstrap/2.2.2/js/bootstrap.min.js"></script>

        <script type="text/template" id="table-tmpl">
          <h3>Links</h3>
          <table class="table table-striped">
            <thead>
              <tr>
                <th>URL</th>
                <th>OP</th>
                <th>Tid</th>
                <th>Detaljer</th>
              </tr>
            </thead>
            <tbody>
            </tbody>
          </table>
        </script>

        <script type="text/template" id="table-row-tmpl">
          <td><a href="<%= url %>"><%= url %></a></td>
          <td><%= posters[0][0] %></td>
          <td><%= new Date(parseInt(posters[0][1])).toLocaleString() %></td>
          <td><a href="#" class="more">more</a></td>
        </script>

        <script type="text/template" id="details-modal-tmpl">
          <div class="modal hide fade">
            <div class="modal-header">
              <button type="button" class="close" data-dismiss="modal" aria-hidden="true">&times;</button>
              <h3>Link details</h3>
            </div>
            <div class="modal-body">
              <h4>URL</h4>
              <a href="<%= url %>"><%= url %></a>
              <h4>Posts</h4>
              <ul>
                <% _.each(posters, function(poster) { %>
                  <li><%= poster[0] %> - <%= new Date(parseInt(poster[1])).toLocaleString() %></li>
                <% }); %>
              </ul>
            </div>
          </div>
        </script>

        <script type="text/template" id="filters-tmpl">
          <h3>Filters</h3>
          <div class="filters"><span class="label all">ALL</span><span class="label none">NONE</span></div>
        </script>


        <script>
          var Nick = Backbone.Model.extend({
            defaults: {
              selected: true
            }
          });

          var Links = Backbone.Collection.extend({
          });

          var Nicks = Backbone.Collection.extend({
            model: Nick,

            toggleNick: function(model) {
              model.set("selected", !!!model.get("selected"));
              this.trigger("selected");
            },

            deselectAll: function() {
              this.each(function(nick) {
                nick.set("selected", false);
              });
              this.trigger("selected");
            },

            selectAll: function() {
              this.each(function(nick) {
                nick.set("selected", true);
              });
              this.trigger("selected");
            },

            isAllSelected: function() {
              return this.every(function(model) {
                return model.get("selected");
              });
            },

            isNoneSelected: function() {
              return this.every(function(model) {
                return !model.get("selected");
              });
            },
          });

          var NickSelector = Backbone.View.extend({
            tagName: "span",

            className: "label",

            events: {
              "click": "toggleNick"
            },

            initialize: function() {
              _.bindAll(this, "render", "toggleNick");
              this.model.on("change", this.render);
            },

            render: function() {
              this.$el.html(this.model.get("nick"));
              if (this.model.get("selected")) {
                this.$el.addClass("label-info");
              } else {
                this.$el.removeClass("label-info");
              }
              return this;
            },

            toggleNick: function(e) {
              this.model.collection.toggleNick(this.model);
            }
          });

          var DetailsView = Backbone.View.extend({
            template: _.template($("#details-modal-tmpl").html()),

            render: function() {
              this.$el.html(this.template(this.model.toJSON()));
              return this;
            },

            show: function() {
              this.$(".modal").modal("show");
            }
          });

          var LinkView = Backbone.View.extend({
            template: _.template($("#table-row-tmpl").html()),

            tagName: "tr",

            initialize: function() {
              _.bindAll(this, "showDetails")
            },

            events: {
              "click .more": "showDetails"
            },

            render: function() {
              this.$el.html(this.template(this.model.toJSON()));
              return this;
            },

            showDetails: function(e) {
              e.preventDefault();
              var detailsView = new DetailsView({
                model: this.model
              });
              $("body").append(detailsView.render().el);
              detailsView.show();
            }
          });

          var FilterView = Backbone.View.extend({
            template: _.template($("#filters-tmpl").html()),

            events: {
              "click .all": "toggleAllFilter",
              "click .none": "toggleNoneFilter"
            },

            initialize: function() {
              _.bindAll(this, "onSelected");
              this.collection.on("selected", this.onSelected);
            },

            render: function() {
              this.$el.html(this.template());
              this.collection.each(function(link) {
                var itemView = new NickSelector({
                  model: link
                });
                this.$(".filters").append(itemView.render().el);
              }, this);
              this.onSelected();
              return this;
            },

            toggleAllFilter: function() {
              this.collection.selectAll();
            },

            toggleNoneFilter: function() {
              this.collection.deselectAll();
            },

            onSelected: function() {
              if (this.collection.isAllSelected()) {
                this.$(".all").addClass("label-warning");
              } else {
                this.$(".all").removeClass("label-warning");
              }
              if (this.collection.isNoneSelected()) {
                this.$(".none").addClass("label-warning");
              } else {
                this.$(".none").removeClass("label-warning");
              }
            }
          });

          var LinksView = Backbone.View.extend({
            template: _.template($("#table-tmpl").html()),

            initialize: function() {
              _.bindAll(this, "render");
              this.nicks = this.options.nicks;
              this.nicks.on("selected", this.render)
            },

            render: function() {
              this.$el.html(this.template());
              this.collection.each(function(link, index) {
                if (this.shouldDisplay(link)) {
                  link.set({index: index + 1});
                  var itemView = new LinkView({
                    model: link
                  });
                  this.$("tbody").append(itemView.render().el);
                }
              }, this);
              return this;
            },

            shouldDisplay: function(link) {
              var selectedNicks = this.nicks.where({selected: true});
              var hasNickMatch = _.any(selectedNicks, function(nick) {
                return _.any(link.get("posters"), function(poster) {
                  return nick.get("nick") === poster[0];
                }, this);
              }, this);
              return hasNickMatch;
            }
          });

          $(function() {
            var links = new Links();
            var nicks = new Nicks();

            links.comparator = function(model1, model2) {
              var a, b;
              a = model1.get("posters")[0][1];
              b = model2.get("posters")[0][1];
              return a === b ? 0 : a < b ? 1 : -1;
            };

            links.reset(#{links});
            nicks.reset(#{nicks});

            var filterView = new FilterView({
              collection: nicks
            });
            var linksView = new LinksView({
              collection: links,
              nicks: nicks
            });


            $("#content").append(filterView.render().el);
            $("#content").append(linksView.render().el);
          });
        </script>
    </body>
</html>
"""