# Post-release check

> **Stub, not written yet.**
> **Purpose:** After the user publishes, confirm the new build really is live and healthy, and tidy up after the release: it landed on production and new servers run it, its analytics events are coming through, errors look normal, and nothing from the release round is left lying around. The automated tests already ran before the publish (RELEASING.md "Before a publish").
>
> **Ideas to confirm with the user when we write it:**
> - **Landed:** a freshly joined server reports the new place version (`game.PlaceVersion`). Old servers keep the previous version until they close; moving them to the latest update from the dashboard is the user's call.
> - **Events coming through:** the new build's analytics events show up in the dashboards. A server-start event carrying the place version would make the new build's traffic easy to spot.
> - **Errors look normal:** the Creator Hub error report compared with the usual level before the publish. Anything new or spiking becomes an incident (`live/INCIDENTS.md`).
> - **No leftovers in the build:** no debug or temporary code outside Studio-only paths, no test values left in configs.
> - **Tidy repo:** merged `agent/*` branches deleted, finished claims removed from `docs/CLAIMS.md`, idle lanes on the new `main`.
> - **When:** right after the publish, and again after the first hour.
