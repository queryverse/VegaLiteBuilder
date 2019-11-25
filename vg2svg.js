'use strict';

const vega = require('vega');

const svgHeader =
  '<?xml version="1.0" encoding="utf-8"?>\n' +
  '<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" ' +
  '"http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">\n';

function read() {
    return new Promise((resolve, reject) => {
        let text = '';

        process.stdin.setEncoding('utf8');
        process.stdin.on('error', err => { reject(err); });
        process.stdin.on('data', chunk => { text += chunk; });
        process.stdin.on('end', () => { resolve(text); });
    });
};

function compile(spec) {
    try {
        const view = new vega.View(vega.parse(spec), {
            // loader: vega.loader({baseURL: base}),   // load files from base path
            // logger: vega.logger(loglevel, 'error'), // route all logging to stderr
            renderer: 'none'                        // no primary renderer needed
          }).finalize();                            // clear any timers, etc

        return view.toSVG().then(
            function(_) {
                process.stdout.write(svgHeader);
                process.stdout.write(_ + '\n');
            });
    }
    catch (err) {
        console.error(err)
        process.exit(1)
    }
}

read()
    .then(text => compile(JSON.parse(text)))
    .catch(err => console.error(err));
