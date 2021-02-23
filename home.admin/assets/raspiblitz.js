require('module-alias/register');
require('module-alias').addPath('.');
require('dotenv').config();

// system imports
const path = require('path');
const fs = require('fs');

// umbrel imports
const constants = require('utils/const.js');
const diskLogic = require('logic/disk.js');
const AUTH = require('logic/auth.js');
const UUID = require('utils/UUID.js');
const SYSTEM_USER = UUID.fetchBootUUID() || 'admin';

// get basic data
console.log("### RASPIBLITZ UTILITIES");
var arguments = process.argv;

// give info if no parameter is given
if (arguments.length < 3) {
    console.log("raspiblitz.js status");
    console.log("raspiblitz.js init-user [USERNAME] [PASSWORD] [SEED-STRING]");
    process.exit();
}

// STATUS
if (arguments[2] == "status") {
    console.log("### STATUS");
    console.log("DEVICE_HOSTNAME='"+constants.DEVICE_HOSTNAME+"'");
    console.log("DEVICE_HOSTS='"+process.env.DEVICE_HOSTS+"'");
    console.log("SYSTEM_USER='"+SYSTEM_USER+"'");
    process.exit();
}

// INIT-USER
if (arguments[2] == "init-user") {
    console.log("### INIT USER");

    if (arguments.length < 5) {
        console.log("missing arguments");
        process.exit();
    }
    const USERNAME = arguments[3];
    const PASSWORD = arguments[4];

    const credentials = AUTH.hashCredentials(SYSTEM_USER, PASSWORD);
    console.log(credentials.password);
    diskLogic.writeUserFile({ name: USERNAME, password: credentials.password, seed: 'fakeseed' });

    // TODO: reproducable & fixed seed maybe use the LND signer on string 'raspiblitz'
    // https://api.lightning.community/?javascript#signmessage-2
}
