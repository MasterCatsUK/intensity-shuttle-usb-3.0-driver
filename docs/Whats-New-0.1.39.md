# Shuttle Camera 0.1.39 — stretch every desktop resolution to the video frame

In **Video Output**, select **Mac desktop** or **Extended display**, stop output if running, then choose **Stretch** from the sizing menu and start output.

Stretch maps the whole desktop to the whole selected video frame. The eleven sizes in the supplied screenshot are supported:1920×1080,1600×1200,1600×900,1344×1008,1344×756,1280×960,1280×720,1024×768,1024×576,960×540 and800×600. Availability in macOS depends on the selected screen.

You can then change the desktop resolution in **System Settings → Displays** while output continues. The desktop now follows that change without restarting the sender or keeping a crop based on the previous dimensions. The USB resolution and cadence remain the format selected in Shuttle Camera: this resizes the desktop picture, not the physical output timing.

Stretch can change proportions: a4:3 desktop fills a16:9 HD picture by making it wider. Choose **Fit** to preserve proportions with borders, or **Fill** to preserve proportions by cropping. Fit/Fill calculate their geometry at output start; restart them after changing desktop resolution. Sizing itself is selected before starting output. Movie and idle-media sizing options remain available.

## Validation

An explicit reversible live probe created its own temporary virtual desktop, then changed it through all eleven listed resolutions with one ScreenCaptureKit stream kept running. A four-colour corner pattern alternated each step to require a fresh frame. All four quadrants had to remain present in the exact output raster. All eleven passed for1920×1080, PAL720×576 and NTSC720×486 output surfaces. The temporary display was removed after each run. No USB capture/output, audio route, normal monitor mode or production preference was changed by these probes. A baseline using the0.1.38 desktop implementation failed on the first live resolution change, confirming the regression check catches the old pinned crop.

The fix leaves ScreenCaptureKit source/destination rectangles unset for Stretch, which means the current whole display fills the fixed output surface. Explicit Fit/Fill geometry is unchanged. Native build, existing isolated GUI checks and installer payload checks run before delivery. Physical TV timing has not been newly qualified by these software display tests.

Host39 and the desktop sender are updated. Camera17/output12/HAL3/Premiere1 and their interfaces remain unchanged. Stop output/capture and quit camera apps, editors and Shuttle Camera before installing0.1.39. No driver reactivation is needed when already enabled. The existing development signing/security setup and experimental virtual-display interface caveats remain unchanged.

The user confirmed PAL and NTSC extended displays both appear and work on installed0.1.38. Their1024×768 starting desktop and separate SD/HD screen identities are retained; macOS can offer further desktop scaling choices. See Whats-New-0.1.38.md for those changes.
