# Accept one complete mailbox, either bare or in the standard display-name form.
function Resolve-QOTicketEmailAddress {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value) -or $Value -match '[\r\n]') { return '' }
    $text = $Value.Trim()
    try {
        $addresses = [Net.Mail.MailAddressCollection]::new()
        $addresses.Add($text)
        if ($addresses.Count -ne 1) { return '' }
        $address = $addresses[0].Address
    } catch { return '' }

    if ([string]::Equals($text, $address, 'Ordinal')) { return $address }
    $opening = $text.LastIndexOf('<')
    if ($opening -lt 0 -or !$text.EndsWith('>')) { return '' }
    $displayName = $text.Substring(0, $opening).Trim()
    if ($displayName -match '[<>]' -or ($displayName -match '[@;,]' -and $displayName -notmatch '^"(?:[^"\\]|\\.)*"$')) { return '' }
    $inside = $text.Substring($opening + 1, $text.Length - $opening - 2).Trim()
    if ([string]::Equals($inside, $address, 'Ordinal')) { return $address }
    return ''
}
