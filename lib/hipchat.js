key = process.env.HIPCHAT_API_KEY;

module.exports = HipchatWrapper;

var Hipchat = require('node-hipchat');

var client;

function HipchatWrapper(robot) {
  if (client) return client;
  this.robot = robot;
  if (robot.adapter.repl) {
    robot.logger.info('Using fake hipchat client');
    client = this.client = null;
  } else {
    robot.logger.info('Using real hipchat client');
    client = this.client = new Hipchat(key);
  }
}

HipchatWrapper.prototype.postMessage = function(params, hubotMessage) {
  if (this.client) {
    if (hubotMessage) {
      params.room = hubotMessage.envelope.message.room;
    }
    this.client.postMessage(params);
  } else {
    if (hubotMessage) {
      hubotMessage.send(params.message);
    } else {
      this.robot.messageRoom('shell', params.message)
    }
  }
};