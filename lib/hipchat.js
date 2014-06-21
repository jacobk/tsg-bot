module.exports = HipchatWrapper;

var Hipchat = require('node-hipchat');

function HipchatWrapper(robot, key) {
  if (robot.adapter.repl) {
    robot.logger.info('Using fake hipchat client');
    this.client = null;
  } else {
    robot.logger.info('Using real hipchat client');
    this.client = new Hipchat(key);
  }
}

HipchatWrapper.prototype.postMessage = function(params, hubotMessage) {
  if (this.client) {
    params.room = hubotMessage.envelope.message.room
    console.log(params);
    this.client.postMessage(params);
  } else {
    hubotMessage.send(params.message);
  }
};