# -*- coding: utf-8 -*-
# Copyright © 2013 Zulip, Inc.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

VERSION = "0.1.0"
API_VER = "v1"

request = require('request')
{EventEmitter} = require 'events'

class @Client extends EventEmitter
    constructor: (options) ->
        @email = options.email
        @api_key = options.api_key
        @verbose = options.verbose ? true

        site = options.site ? "https://api.zulip.com"

        if site != "https://api.zulip.com" and not /\/api$/.test(site)
            site = "#{site}/api"

        @base_url = site

        @client_name = options.client_name ? "API: Node"
        @failures = 0

    doAPIQuery: (method='POST', url, orig_request, cb) ->
        req = {
            client: @client_name
        }

        for k,v of orig_request
            req[k] = if v instanceof Object then JSON.stringify(v) else v

        opts =
            url: "#{@base_url}/#{url}"
            method: method
            form: (req if method != "GET")
            qs: (req if method == "GET")
            auth:
                user: @email
                pass: @api_key
            strictSSL: true
            encoding: 'utf8'

        request opts, (error, response, body) =>
            if (not error) and (response.statusCode < 200 or response.statusCode >= 300)
                error = new Error("Request failed with status #{response.statusCode}: #{body?.slice(0, 100)}")
                error.statusCode = response.statusCode

            try
                body = JSON.parse(body) if body
            catch e
                console.warn("Zulip API: Error parsing JSON:", body.slice(0, 60)) if @verbose
                body = null

            if error
                console.warn("Zulip API Error: #{error.message} ") if @verbose

            cb(error, body) if cb?

    registerEventQueue: (opts = {}) ->
        @queue_id = null
        @last_event_id = null

        opts.event_types ?= []
        @register_opts = opts

        @doAPIQuery 'POST', "#{API_VER}/register", opts,  (error, response) =>
            throw error if error

            @register_response = response
            @emit('registered', response)

            @queue_id = response.queue_id
            @last_event_id = response.last_event_id

            @_poll()

    _poll: =>
        req = {@queue_id, @last_event_id}
        @doAPIQuery 'GET', "#{API_VER}/events", req, (error, response) =>
            if error or not response
                if error?.statusCode
                    msg = response?.msg ? ""
                    if error.statusCode == 400 and msg.indexOf("Bad event queue id") != -1
                        # Our event queue went away, probably because we were
                        # asleep or the server restarted abnormally.  We may
                        # have missed some events while the network was down
                        # or something, but there's not really anything we can
                        # do about it other than resuming getting new ones.
                        return @registerEventQueue(@register_opts)
                    else if error.statusCode >= 400 and error.statusCode < 500
                        if @failures > 3
                            throw error

                @failures += 1
                backoff = Math.min(Math.exp(@failures / 2.0), 30) * 1000
                console.warn("Zulip API: Get events failure #{@failures}, retry in #{Math.round(backoff/1000)}s") if @verbose
                setTimeout(@_poll, backoff)
                return

            for event in response.events
                @last_event_id = Math.max(@last_event_id, event.id)
                @emit('event', event)

                switch event.type
                    when 'message'
                        @emit('message', event.message)

            if @failures > 0
                console.warn("Zulip API: Event queue reconnected")
                @failures = 0

            @_poll()

    makeQueryFn = (method, endpoint) ->
        return (req, cb) ->
            @doAPIQuery(method, "#{API_VER}/#{endpoint}", req, cb)

    sendMessage: makeQueryFn('POST', 'messages')
    getMembers: makeQueryFn('GET', 'users')
    listSubscriptions: makeQueryFn('GET', 'users/me/subscriptions')
