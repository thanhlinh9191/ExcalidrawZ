const originalConsole = console;
const methods = ['log', 'debug', 'info', 'warn', 'error'];
const maxConsoleArgLength = 500;
const maxConsoleObjectKeys = 12;

function truncateConsoleString(value) {
    if (value.length <= maxConsoleArgLength) {
        return value;
    }
    return value.slice(0, maxConsoleArgLength - 3) + '...';
}

function summarizeConsoleArg(arg) {
    if (arg === null) {
        return 'null';
    }
    if (arg === undefined) {
        return 'undefined';
    }

    const type = typeof arg;
    if (type === 'string') {
        return truncateConsoleString(arg);
    }
    if (type === 'number' || type === 'boolean' || type === 'bigint') {
        return String(arg);
    }
    if (type === 'function') {
        return `[Function ${arg.name || 'anonymous'}]`;
    }
    if (arg instanceof Error) {
        return truncateConsoleString(arg.stack || arg.message || String(arg));
    }
    if (Array.isArray(arg)) {
        return `[Array(${arg.length})]`;
    }
    if (type === 'object') {
        const constructorName = arg.constructor && arg.constructor.name
            ? arg.constructor.name
            : 'Object';
        let keys = [];
        try {
            keys = Object.keys(arg).slice(0, maxConsoleObjectKeys);
        } catch (error) {
            return `[${constructorName}]`;
        }
        const suffix = keys.length > 0 ? ` keys=${keys.join(',')}` : '';
        return `[${constructorName}${suffix}]`;
    }

    return truncateConsoleString(String(arg));
}

methods.forEach(function (method) {
    const originalMethod = console[method];
    console[method] = function (...args) {
        originalMethod.apply(originalConsole, args);
        try {
            window.webkit.messageHandlers.consoleHandler.postMessage({
                event: 'log',
                method: method,
                args: args.map(summarizeConsoleArg)
            });
        } catch (e) {
            originalConsole.error('Error posting message...', e);
        }
    };
});


window.onerror = function(message, source, lineno, colno, error) {
   console.error(message, source, lineno, colno, error);
};
