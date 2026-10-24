# GanJi v90 — iOS native bottom layout refinement

Based on the previous GanJi v89 source.

## Layout changes
- Extends the solid system-background surface behind the fixed location/search capsule and bottom Dock.
- Removes the exposed map-texture strip between the market sheet and the bottom controls.
- Keeps the existing market sheet height/drag behavior, search, region picker, map annotations, market data, and favorites logic unchanged.

## Build
Upload the project to GitHub and run the existing Actions workflow. This source has not been compiled with Xcode in this environment.


## v91 search behavior fix
- Tapping/focusing the place search field no longer hides the nearby-markets panel.
- Search suggestions and place selection behavior remain unchanged; selecting a result can still dismiss the keyboard and restore the panel as before.
