// Amp's plain usage output; no I/O or credential access.
function read(response) {
    const quotas = [];
    let email = null;
    const labels = {"amp free":"Free", "individual credits":"Individual"};
    for (const raw of response.text.split(/\r?\n/)) {
        const line = raw.trim();
        const account = line.match(/Signed in as\s+(\S+)\s+\(/);
        if (!email && account) email = account[1];
        const capped = line.match(/^(.+?):\s*\$([0-9]+(?:\.[0-9]+)?)\s*\/\s*\$([0-9]+(?:\.[0-9]+)?)\s+remaining/i);
        if (capped) {
            // Dollars of a ceiling are money of that ceiling — "$17.59 of $20.00" (the Left law).
            if (Number(capped[3]) > 0) quotas.push({type:"model", name:labels[capped[1].trim().toLowerCase()] || capped[1].trim(),
                left:{money:capped[2], of:capped[3], currency:"USD"}});
            continue;
        }
        const balance = line.match(/^(.+?):\s*\$([0-9]+(?:\.[0-9]+)?)\s+remaining/i);
        if (balance) quotas.push({type:"model", name:labels[balance[1].trim().toLowerCase()] || balance[1].trim(),
            left:{money:balance[2],currency:"USD"}});
    }
    if (!quotas.length) return {error:{parseFailed:"No valid credit lines found in amp usage output"}};
    return {quotas:quotas, account:{email:email}};
}
