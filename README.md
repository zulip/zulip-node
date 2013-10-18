### Installing

```
npm install zulip
```

### Using the API

For now, the only fully supported API operation is sending a message.
The other API queries work, but are under active development, so
please make sure we know you're using them so that we can notify you
as we make any changes to them.

You can obtain your Zulip API key, create bots, and manage bots all
from your Zulip [settings page](https://zulip.com/#settings).

A typical simple bot sending API messages will look as follows:

    var zulip = require('zulip');
    var client = new zulip.Client({
        email: "your-bot@zulip.com",
        api_key: "your_32_character_api_key",
        verbose: true
    });

    client.sendMessage({
        type: "stream",
        content: 'Zulip rules!',
        to: ['stream_name'],
        subject: "feedback"
    });

Additional examples:

    client.sendMessage({
        type: "private",
        content: "Zulip rules!",
        to: ['user1@example.com']
    });

    client.sendMessage({
        type: "stream",
        content: 'Zulip rules!',
        to: ['stream_name'],
        subject: "feedback"
    }, function (error, response) {
        if (error) {
            console.log("Something went wrong!", error);
        } else {
            console.log("Message sent!");
        }
    });
