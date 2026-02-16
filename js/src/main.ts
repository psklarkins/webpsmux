import { ConnectionFactory } from "./websocket";
import { Terminal, WebTTY, protocols } from "./webtty";
import { OurXterm } from "./xterm";

// @TODO remove these
declare var gotty_auth_token: string;
declare var gotty_term: string;
declare var gotty_ws_query_args: string;

const elem = document.getElementById("terminal")

if (elem !== null) {
    var term: Terminal;
    term = new OurXterm(elem);

    const base = window.location.href.endsWith("/") ? window.location.href : window.location.href + "/";
    const wsUrl = new URL("ws", base);
    wsUrl.protocol = (window.location.protocol === "https:") ? "wss:" : "ws:";
    wsUrl.search = gotty_ws_query_args === "" ? "" : gotty_ws_query_args;

    const args = window.location.search;
    const factory = new ConnectionFactory(wsUrl.toString(), protocols);
    const wt = new WebTTY(term, factory, args, gotty_auth_token);
    const closer = wt.open();

    // According to https://developer.mozilla.org/en-US/docs/Web/API/Window/unload_event
    // this event is unreliable and in some cases (Firefox is mentioned), having an
    // "unload" event handler can have unwanted side effects. Consider commenting it out.
    window.addEventListener("unload", () => {
        closer();
        term.close();
    });
};
