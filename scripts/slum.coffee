# Description:
#   Random sins
#
# Commands:
#   hubot fake - ziggi zack zack

module.exports = (robot) ->
  robot.respond /DUMP MSG/, (msg) ->
    msg.send JSON.stringify(msg)

  robot.hear /^THEN WHO WAS I$/, (msg) ->
    msg.send "MSG PROPS: #{[k for k of msg]}"
    msg.send "THEN YOU MUST WAS... #{JSON.stringify(msg.message.user,null,2)}!"
