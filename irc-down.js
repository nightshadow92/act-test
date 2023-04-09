const XDCC = require('xdccjs').default
const fs = require('fs');


let opts = {
    host: 'irc.rizon.net', // IRC hostname                                                   - required
    port: 6667, // IRC port                                                                   - default: 6667
    retry: 1, // Nb of retries before skip                                                    - default: 1
    timeout: 1, // Nb of seconds before a download is considered timed out                   - default: 30
    verbose: true, // Display download progress and jobs status                               - default: false
    botNameMatch: false,
    path: process.cwd()
}
const xdccclient = new XDCC(opts)

xdccclient.on('ready', async () => {
    process.argv.slice(2).forEach(function (val) {
        xdccclient.download('Ginpachi-Sensei', [val])
    });

    xdccclient.on('can-quit', () => {
        xdccclient.quit()
    })
})
