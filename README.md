# fix-roblox-thumbnails

**English** | [Русский](README.ru.md)

A single `.bat` that brings back images in Roblox on Russian ISPs:
game (place) thumbnails, avatars, icons, screenshots, Studio toolbox previews.

```
fix-roblox-thumbnails.bat            install
fix-roblox-thumbnails.bat /remove    delete the added lines
fix-roblox-thumbnails.bat /rollback  restore hosts from the backup
fix-roblox-thumbnails.bat /help      help
```

## What is broken

Roblox serves every image from `tr.rbxcdn.com`. Since July 2026 that name stops
resolving on Russian ISPs: DNS returns a `CNAME` to `trns1.rbxcdn.com`, and that
name has neither an `A` nor an `AAAA` record.

Measured on a live machine, November 2026:

| Query | Answer |
|---|---|
| system DNS (router `192.168.1.1`) | `CNAME trns1.rbxcdn.com`, then nothing |
| `1.1.1.1` | same, NODATA |
| `8.8.8.8` | same, NODATA |
| Cloudflare DoH (JSON) | `Status: 0`, CNAME only, single SOA in Authority |
| `trns1.rbxcdn.com` A and AAAA | empty, both |

The zone itself is fine: `setup.rbxcdn.com` happily resolves into CloudFront
(`54.192.35.x`) and `c0.rbxcdn.com` into Akamai (`23.73.2.x`). One name is
broken, not the zone and not the ISP.

Hand the client an address and the image arrives:

```
curl --resolve tr.rbxcdn.com:443:23.73.2.78 https://tr.rbxcdn.com/180DAY-.../150/150/.../Png/noFilter
HTTP/1.1 200 OK, image/Png, 3739 bytes
```

In the client log it looks like this:

```
[DFLog::HttpTraceError] CURLOPT_ERRORBUFFER: Could not resolve host: tr.rbxcdn.com
HttpResponse(#330 ...) time:11.6ms error:2 message:HttpError: DnsResolve
```

Titles, ratings and player counts are still there, because they come from
`*.roblox.com` APIs, which resolve normally. That is how you recognise it:
text yes, images no.

## Why a DPI bypass does not help

zapret's `winws` breaks DPI inside an already established connection - it needs
an IP to work with. When DNS returns no address there is nothing to desync:
no strategy, no strategy tournament and no hostlist edit can fix this. It is a
name resolution problem, not a packet problem.

## What the script does

1. Checks whether `tr.rbxcdn.com` lines already exist. If they do, it changes
   nothing and does not even raise a UAC prompt.
2. Backs up `hosts` to `%USERPROFILE%\roblox-thumbnails-fix\hosts-<date>.txt`.
3. Probes every candidate address over HTTPS (`curl --resolve`) and keeps only
   the ones that actually answer. If none answer, it falls back to the built-in
   list and says so.
4. Appends a commented block with the date to `hosts`.
5. Flushes the DNS cache and prints `ping` so you can see it worked.

Running it twice is safe. `/remove` cuts the domain lines after backing the file
up, and aborts without writing anything if the result looks suspiciously empty.

The verdict at the end is coloured, so you do not have to read the middle part:

| Colour | Meaning |
|---|---|
| green | done, the entries are written |
| red | failed, `hosts` was not touched |
| cyan | nothing to change, the entries are already there |

## After installing

Close Roblox completely and open it again. The client caches failed lookups and
will not retry on its own, so without a restart the grey boxes stay.

## Caveats

- The addresses are CDNs (CloudFront and Akamai) and they rotate. If images go
  grey again in a few months: `/remove` and run it again. The list lives in the
  `IPS` variable at the top of the script.
- `hosts` applies to the whole machine, including the website and Studio. That
  is exactly what is needed here - all three were broken.
- Dependencies are `curl.exe` and PowerShell, both built into Windows 10 and 11.
  Without `curl` the script writes the built-in list unverified; without
  PowerShell the verdict prints uncoloured.
- The script sends nothing anywhere and touches nothing except `hosts` and its
  own backup folder.

## Background

- Roblox bug report: `devforum.roblox.com/t/cdn-subdomain-trrbxcdncom-does-not-work-in-russia-avatarsgame-iconsthumbnails-do-not-load/4757714`
  (internal ticket `CREATORBUG-27611`, since 26 July 2026).
- Related thread in the zapret bundle upstream: `github.com/Flowseal/zapret-discord-youtube/discussions/16296`.

Tested on Windows 11 10.0.26100, Roblox 0.745.
