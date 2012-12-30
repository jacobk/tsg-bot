# Description:
#   Keep track of links
#
# Dependencies:
#   "moment": "~1.7.2"
#
# Configuration:
#   None
#
# Commands:
#   hubot link me <link id> - Posts link with that id from the link archive
#   hubot links - Provides a link to the links archive page
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
moment = require "moment"

version = "2"

module.exports = (robot) ->

  robot.brain.on "loaded", ->
    robot.brain.data.links ?=
      version: version
      index: 0
      db: {}
      posters: {}
    brain_version = robot.brain.data.links.version
    if brain_version isnt version
      throw "Wrong link-archive version want: #{version} got: #{brain_version}"

  robot.hear util.pattern, (msg) ->
    links = robot.brain.data.links
    url   = util.normalize msg.match[1]
    nick  = msg.message.user.name
    link  = links.db[util.md5hash url] ?=
      id: ++links.index
      url: url
      posters: []
    post  =
      nick: nick
      ts: new Date().getTime()

    link.posters.push post
    links.posters[nick] = (links.posters[nick] ? 0) + 1
    op = link.posters[0]

    if op.nick isnt nick
      msg.reply "#{op.nick} posted the same link #{moment(new Date(op.ts)).fromNow()}"
    robot.brain.save()

  robot.respond /links$/i, (msg) ->
    msg.send process.env.HEROKU_URL + "hubot/links"

  robot.respond /(link|url)( me)? (\d+)/i, (msg) ->
    db = robot.brain.data.links.db
    id = parseInt msg.match[3], 10
    links = for hash, link of db when link.id is id
      link
    link = links.pop()
    if link
      msg.send "op: #{link.posters[0].nick} url: #{link.url}"
    else
      msg.reply "Sorry, no link with that id"

  robot.router.get '/hubot/links', (req, res) ->
    links = for hash, link of robot.brain.data.links.db
      link
    posters = for nick, count of robot.brain.data.links.posters
      nick: nick
      count: count
    res.setHeader 'Content-Type', 'text/html'
    res.end pageContent(JSON.stringify(links), JSON.stringify(posters))


util =
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


pageContent = (links, posters) ->
  """
<!DOCTYPE html>
    <head>
        <meta charset="utf-8">
        <title>Links!</title>
        <link href="//netdna.bootstrapcdn.com/twitter-bootstrap/2.2.2/css/bootstrap-combined.min.css" rel="stylesheet">
        <style>
          body {
            margin-top: 25px;
          }
          .btn-toolbar > .btn-group, .btn-toolbar > .btn + .btn, .btn-toolbar > .btn-group + .btn, .btn-toolbar > .btn + .btn-group {
            margin-left: 0px;
            margin-right: 5px;
          }
          .btn-toolbar > .btn-group {
            vertical-align: baseline;
          }
          .btn-toolbar {
            line-height: 34px;
            ver
          }
          .link-table {
              table-layout: fixed;
              word-wrap: break-word;
              word-break: break-all;
          }
        </style>
    </head>
    <body>
        <div class="container">
          <div class="row">
            <div id="search-filters" class="span12"></div>
          </div>
          <div class="row">
            <div id="nick-filters" class="span12"></div>
          </div>
          <div class="row">
            <div id="content" class="span12"></div>
          </div>
        </div>
        <script src="//ajax.googleapis.com/ajax/libs/jquery/1.8.3/jquery.min.js"></script>
        <script src="//cdnjs.cloudflare.com/ajax/libs/underscore.js/1.4.3/underscore-min.js"></script>
        <script src="//cdnjs.cloudflare.com/ajax/libs/backbone.js/0.9.9/backbone-min.js"></script>
        <script src="//netdna.bootstrapcdn.com/twitter-bootstrap/2.2.2/js/bootstrap.min.js"></script>
        <script src="//cdnjs.cloudflare.com/ajax/libs/moment.js/1.7.2/moment.min.js"></script>

        <script type="text/template" id="table-tmpl">
          <table class="link-table table table-striped">
            <thead>
              <tr>
                <th width="5%">ID</th>
                <th width="65%">URL</th>
                <th width="10%">OP</th>
                <th width="5%">#</th>
                <th width="15%">FIRST</th>
                <th width="5%"><i class="icon-info-sign"></i></th>
              </tr>
            </thead>
            <tbody>
            </tbody>
          </table>
        </script>

        <script type="text/template" id="table-row-tmpl">
          <td><a href="#" class="more"><%= id %></a></td>
          <td><a href="<%= url %>"><%= url %></a></td>
          <td><%= posters[0].nick %></td>
          <td><%= posters.length %></td>
          <td>
            <a href="#" class="post-date" rel="tooltip" title="<%= moment(new Date(posters[0].ts)).format("YYYY-MM-DD HH:mm") %>"><%= moment(new Date(posters[0].ts)).fromNow() %></a>
          </td>
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
                  <li><%= poster.nick %> - <%= moment(new Date(poster.ts)).format("YYYY-MM-DD HH:mm") %></li>
                <% }); %>
              </ul>
            </div>
          </div>
        </script>

        <script type="text/template" id="filters-tmpl">
          <div class="filters">
            <div class="btn-toolbar">
              <div class="btn-group">
                <button class="btn all">ALL</button><button class="btn none">NONE</button>
              </div>
            </div>
          </div>
        </script>

        <script type="text/template" id="search-filters-tmpl">
          <input type="text" class="span12 filter-query" placeholder="Sök länk">
        </script>

        <script type="text/template" id="nick-button-tmpl">
          <span class="label label-inverse"> <%= count %></span> <%= nick %>
        </script>


        <script>
          var Nick = Backbone.Model.extend({
            defaults: {
              selected: true
            }
          });

          var SearchQuery = Backbone.Model.extend({
            defaults: {
              query: ""
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
            template: _.template($("#nick-button-tmpl").html()),

            tagName: "button",

            className: "btn",

            events: {
              "click": "toggleNick"
            },

            initialize: function() {
              _.bindAll(this, "render", "toggleNick");
              this.model.on("change", this.render);
            },

            render: function() {
              this.$el.html(this.template(this.model.toJSON()));
              if (this.model.get("selected")) {
                this.$el.addClass("btn-info");
              } else {
                this.$el.removeClass("btn-info");
                this.$(".label").removeClass("label-inverse");
              }
              return this;
            },

            toggleNick: function(e) {
              this.model.collection.toggleNick(this.model);
            }
          });

          var SearchFilter = Backbone.View.extend({
            template: _.template($("#search-filters-tmpl").html()),

            events: {
              "keyup .filter-query": "searchChanged"
            },

            initialize: function() {
              _.bindAll(this, "render", "searchChanged");
            },

            render: function() {
              this.$el.html(this.template());
              return this;
            },

            searchChanged: _.throttle(function(e) {
              var val = $(e.currentTarget).val();
              this.model.set("query", val);
            }, 500)
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
              _.bindAll(this, "showDetails");
            },

            events: {
              "click .more": "showDetails"
            },

            render: function() {
              this.$el.html(this.template(this.model.toJSON()));
              this.$(".post-date").tooltip();
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
                this.$(".btn-toolbar").append(itemView.render().el);
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
                this.$(".all").addClass("btn-warning");
              } else {
                this.$(".all").removeClass("btn-warning");
              }
              if (this.collection.isNoneSelected()) {
                this.$(".none").addClass("btn-warning");
              } else {
                this.$(".none").removeClass("btn-warning");
              }
            }
          });

          var LinksView = Backbone.View.extend({
            template: _.template($("#table-tmpl").html()),

            initialize: function() {
              _.bindAll(this, "render");
              this.nicks = this.options.nicks;
              this.query = this.options.query;
              this.nicks.on("selected", this.render)
              this.query.on("change:query", this.render)
            },

            render: function() {
              this.$el.html(this.template());
              this.collection.each(function(link) {
                if (this.shouldDisplay(link)) {
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
                  return nick.get("nick") === poster.nick;
                }, this);
              }, this);

              if (!hasNickMatch) return false;

              var isMatchingQuery = false;
              var query = this.query.get("query");
              if (/^\s*$/.test(query)) {
                isMatchingQuery = true;
              } else {
                var queryPattern = new RegExp(query.split("").join(".*"), "i");
                isMatchingQuery = queryPattern.test(link.get("url"));
              }

              return isMatchingQuery;
            }
          });

          $(function() {
            var links = new Links();
            var nicks = new Nicks();
            var query = new SearchQuery();

            links.comparator = function(model1, model2) {
              var a, b;
              a = model1.get("id");
              b = model2.get("id");
              return a === b ? 0 : a < b ? 1 : -1;
            };

            links.reset(#{links});
            nicks.reset(#{posters});

            var filterView = new FilterView({
              collection: nicks
            });
            var searchFilterView = new SearchFilter({
              model: query
            });
            var linksView = new LinksView({
              collection: links,
              nicks: nicks,
              query: query
            });


            $("#nick-filters").append(filterView.render().el);
            $("#search-filters").append(searchFilterView.render().el);
            $("#content").append(linksView.render().el);
            $(".filter-query").focus();
          });
        </script>
    </body>
</html>
"""