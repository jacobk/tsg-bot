module.exports = Wrapper;

var client;

function Wrapper(robot) {
  if (client) return client;
  this.robot = robot;
  this.shell = false;
  if (robot.adapter.repl) {
    robot.logger.info('Using fake slack client');
    this.shell = true;
  } else {
    robot.logger.info('Using real slack');
  }
}

Wrapper.prototype.postMessage = function(params, hubotMessage) {
  console.log('SLACK postMessage', params);
  if (!this.shell) {
    if (hubotMessage) {
      params.message = hubotMessage.message;
    }
    this.robot.emit('slack-attachment', params);
  } else {
    if (hubotMessage) {
      hubotMessage.send(params.message);
    } else {
      this.robot.messageRoom('shell', params.message);
    }
  }
};

    // fields = []
    // fields.push
    //   title: "Field 1: Title"
    //   value: "Field 1: Value"
    //   short: true

    // fields.push
    //   title: "Field 2: Title"
    //   value: "Field 2: Value"
    //   short: true

    // payload =
    //   message: msg.message
    //   content:
    //     text: "Attachement Demo Text"
    //     fallback: "Fallback Text"
    //     pretext: "This is Pretext"
    //     color: "#FF0000"
    //     fields: fields
Wrapper.prototype.params = function(from, message) {
  return {
    username: from,
    content: {
      text: message,
      fallback: message,
      color: "#CCCCCC",
      mrkdwn_in: ['text']
    }
  };
};
