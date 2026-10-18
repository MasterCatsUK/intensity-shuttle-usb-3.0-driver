from pathlib import Path
import html,base64,re,json,hashlib
from reportlab.platypus import SimpleDocTemplate,Paragraph,Spacer,Image,Table,TableStyle,PageBreak,KeepTogether
from reportlab.lib import colors
from reportlab.lib.styles import getSampleStyleSheet,ParagraphStyle
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from PIL import Image as PILImage

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'docs/user-guide'
OUT.mkdir(parents=True,exist_ok=True)
links={
'sip':('Apple: disabling and enabling SIP','https://developer.apple.com/documentation/security/disabling-and-enabling-system-integrity-protection'),
'recovery':('Apple: Recovery on Apple silicon','https://support.apple.com/guide/mac-help/mchl82829c17/mac'),
'extension':('Apple: testing system extensions','https://developer.apple.com/documentation/driverkit/debugging-and-testing-system-extensions'),
'gatekeeper':('Apple: opening apps safely','https://support.apple.com/en-gb/102445')}
PAGES=[]
def page(title):
 p={'title':title,'blocks':[]};PAGES.append(p);return p['blocks']
def p(b,t):b.append(('p',t))
def h(b,t):b.append(('h',t))
def steps(b,items):b.append(('steps',items))
def bullets(b,items):b.append(('bullets',items))
def code(b,t):b.append(('code',t))
def image(b,file,caption):b.append(('image',(file,caption)))
def table(b,headers,rows):b.append(('table',(headers,rows)))
def link(key):title,url=links[key];return f'<a href="{url}">{title}</a>'


b=page('Read this first')
p(b,'<b>Shuttle Camera 0.1.39</b> - Installation and user guide - 18 October 2026')
p(b,'Capture PAL/NTSC VHS, play movie files, monitor Final Cut Pro or Premiere Pro, and send a Mac desktop through the Intensity Shuttle USB 3.0.')
b.append(('notice','<b>Experimental development build.</b> The installer is unsigned; its components are ad-hoc signed and not notarized. The current installer requires SIP disabled. Read Security preparation before deciding to install. This is an independent project, not an official Blackmagic Design driver.'))
h(b,'Requirements')
bullets(b,['Apple-silicon Mac and macOS 27 or later. Testing was on one Mac Studio with macOS 27.0.1; other machines/releases are not comprehensively qualified.','Intensity Shuttle USB 3.0, working USB 3 cable/adapter, and administrator access. Intel Macs and the Thunderbolt Shuttle are not included.','VCR with S-Video or composite and RCA stereo for tape capture. A compatible TV/monitor or recorder for playback.'])
h(b,'One device, two workflows')
p(b,'The Capture tab configures the camera feed; record with a separate camera app such as QuickTime Player. Video Output sends movies, editor frames or a desktop to the device. Capture and playback share the USB interface: use one at a time.')
h(b,'What is new')
p(b,'Live input picture adjustments, capture-resolution retention, idle pictures/movies with a delay, connector-format choices, desktop mirroring, experimental extended display, and Stretch that follows live desktop resolution changes.')
p(b,'The following pages cover security, installation, capture, Picture, movie output, Final Cut, Premiere, desktops, scaling, idle screens, audio/overlays, troubleshooting and removal. Screenshots are current native app views rendered with demonstration settings. They contain no personal footage; selected values are examples.')

b=page('Security preparation')
p(b,'SIP protects macOS. Disabling it weakens protection across the Mac. Apple describes this as temporary development use; restore it after testing. '+link('sip')+'.')
h(b,'The tested development setup')
steps(b,['Save work, back up important files and shut down. On Apple silicon, hold the power button until startup options appear. Choose <b>Options > Continue</b> and authenticate when requested. '+link('recovery')+'.','In Recovery choose <b>Utilities > Terminal</b>. Run the following, then restart into normal macOS.'])
code(b,'csrutil disable')
p(b,'Check the status in normal Terminal:')
code(b,'csrutil status')
p(b,'The installer requires the fully disabled status; partial-disable combinations are not qualified. No supplied build script changes SIP. Building source alone does not require changing security.')
h(b,'Extension developer mode')
p(b,'Apple describes developer mode as relaxing the location check for extensions loaded outside normal application directories. The supplied installer puts the host in Applications. For developers reproducing the outside-Applications build setup, the command is: '+link('extension')+'.')
code(b,'sudo systemextensionsctl developer on')
p(b,'This is separate from screen-recording permission. Do not use it as a generic fix for camera or microphone access.')
h(b,'Restoration and limits')
p(b,'Use the removal/restoration steps at the end when finished. Continued operation after reenabling SIP has not been qualified for this ad-hoc build. This guide does not require disabling FileVault, authenticated-root protection or Gatekeeper globally, or enabling kernel extensions.')

b=page('Install and enable')
steps(b,['Obtain <b>Shuttle-Capture-0.1.39.pkg</b> from a trusted project release. The GitHub source-code ZIP is not the installer. Compare its SHA-256 with the release checksums.','Disable editor external output. Stop capture/playback and quit Shuttle Camera, the editors and camera apps.','Open the package, check that its heading says <b>0.1.39</b>, and install on the current startup volume. Enter your administrator password in macOS when requested.','If macOS blocks an unsigned package, verify its source first. If you choose to proceed, use the specific package exception under Privacy & Security where offered; do not globally disable Gatekeeper. '+link('gatekeeper')+'.'])
h(b,'First installation: enable the drivers')
steps(b,['Open Shuttle Camera from Applications. Choose <b>Help > Driver Setup > Enable Camera</b>. For editor output, choose <b>Enable HDMI Output</b>.','Approve <b>Shuttle Camera Extension</b> and <b>Shuttle HDMI Output Extension</b> under System Settings > General > Login Items & Extensions > Camera Extensions.','Reopen Shuttle Camera and camera/editor clients after activation. Restart only if macOS requests it or the installed audio driver has not loaded.'])
p(b,'An existing camera 17/output 12 installation does not need reactivation for this update. The installer backs up replaced bundles. An unchanged audio driver avoids a Core Audio restart; a first-time audio installation may briefly interrupt sound.')
h(b,'Check the package')
code(b,'shasum -a 256 /path/to/Shuttle-Capture-0.1.39.pkg')
p(b,'Compare the whole result with the matching release SHA256SUMS.txt. A checksum verifies file identity, not publisher trust or notarization.')

b=page('Capture VHS')
image(b,'capture.png','Capture controls with example PAL/S-Video settings. Match the cable and tape standard.')
steps(b,['Connect VCR video OUT to the matching Shuttle input and red/white audio OUT to its RCA inputs. Connect USB 3 and play the tape.','Choose <b>PAL</b> or <b>NTSC</b>, the video input, <b>Analog RCA</b>, resolution and signal-loss behaviour. Close previews and click <b>Apply</b>.','In QuickTime choose <b>File > New Movie Recording</b>. Select the Shuttle camera and <b>Intensity Shuttle - Stereo Audio</b> microphone. Check picture, levels and a short recording before a long transfer.'])
p(b,'PAL sizes: native 720x576, square 768x576, 1280x960 or 1440x1080. NTSC: native 720x480, square 640x480, 1280x960 or 1440x1080. Larger 4:3 sizes are scaled and add no tape detail. Bob deinterlacing gives 50 fps PAL / approximately 59.94 fps NTSC.')
p(b,'Hold last frame or Black preserves capture timing during signal loss; it cannot repair an unstable tape signal. Apply commits format changes. Refresh reloads the active camera settings.')

b=page('Live picture controls')
image(b,'picture.png','Picture controls update the camera feed while a preview is open.')
steps(b,['Start the VCR and open the capture preview. In <b>Picture</b>, leave <b>Live adjustments</b> enabled.','Adjust <b>Brightness</b>, <b>Contrast</b>, <b>Colour</b> (saturation) and <b>Sharpness</b>. Watch the preview while moving a slider.','Use <b>Reset picture</b> for neutral processing. Check your recording before committing a long transfer.'])
p(b,'These are software input-picture adjustments, applied to the camera feed rather than the tape. They do not control HDMI playback colour format. Changing video standard/input/resolution still needs Apply with previews closed.')
p(b,'If controls are unavailable, use Capture > Refresh. An older active camera extension may require activation with previews closed. Do not keep clicking Enable when the current driver is already ready.')

b=page('Movie playback and formats')
image(b,'movie.png','Choose a movie, select Fit/Fill/Stretch and optionally loop it. The filename is illustrative.')
steps(b,['Close camera previews. Select <b>Movie file</b>, click <b>Choose movie</b> and select an output connector and format.','Select sizing, enable <b>Loop</b> if desired and click <b>Start output</b>. Use Stop when finished. The movie supplies its own sound; Use Shuttle Audio is not required for it.'])
table(b,['Output format','Wire raster / cadence'],[['PAL 576i50','720x576 / 50 fields per second'],['NTSC 480i59.94','720x486 / approximately 59.94 fields per second'],['1080i50 /1080i59.94','1920x1080 / 50 or approximately 59.94 fields per second'],['1080p25 /1080p29.97','1920x1080 / 25 or approximately 29.97 frames per second']])
p(b,'S-Video and composite use PAL/NTSC. HDMI/component keep supported SD/HD formats. Compatible connectors may remain active together; the selection constrains formats, not an exclusive switch. Separate HD-plus-downconverted-SD output is not implemented.')

b=page('Final Cut Pro output')
image(b,'output.png','Final Cut output settings and monitoring controls; example values are shown.')
steps(b,['Choose <b>Final Cut Pro</b> and a format appropriate to the timeline. Click <b>Use Shuttle Audio</b> if sound should follow the device.','Click <b>Start Final Cut</b> and wait for <b>Ready for Final Cut</b>. Keep Shuttle Camera open.','In Final Cut Pro 11, choose <b>Settings > Playback > A/V Output > Intensity Shuttle - HDMI Output</b>. Enable <b>Window > A/V Output</b> and play or scrub.','When finished, disable Final Cut A/V Output first, then Stop in Shuttle Camera. Turning A/V Output off alone does not restore the Mac sound route.'])
p(b,'The Shuttle output is SD/HD, not 4K. Rendering/downscaling of a 4K timeline takes place in the editor. Compare the same section with A/V Output off if playback becomes choppy, and check timeline/output cadence before changing driver settings.')

b=page('Premiere Pro output')
image(b,'premiere.png','Premiere source selection. Video and audio are selected separately in Premiere.')
steps(b,['Choose <b>Premiere Pro</b> and the matching format. Click <b>Start Premiere</b> and wait for <b>Ready for Premiere</b>.','In Premiere Pro 2025 Playback settings enable <b>Mercury Transmit</b> and the video stream for <b>Intensity Shuttle - HDMI Output</b>.','In <b>Audio Hardware > Default Output</b> select <b>Intensity Shuttle - HDMI Audio</b>. The Transmit plug-in is video-only; an empty audio-stream column is expected.','Disable Mercury Transmit before stopping output. Restore any explicit Premiere audio-device selection inside Premiere itself.'])
p(b,'Restart Premiere after plug-in installation. Its original Blackmagic Playback entry is separate from this project. If output disappears in the background, check Premiere\'s Disable video output when in the background option. Close one editor\'s external output before using another.')

b=page('Mirror or extend the desktop')
image(b,'extended.png','Extended display with Stretch selected. Start creates a separate Mac desktop.')
steps(b,['Choose <b>Mac desktop</b> to mirror an existing screen, or <b>Extended display</b> for a separate desktop. Select connector, video format and sizing.','Grant <b>Screen & System Audio Recording</b> permission to Shuttle Camera in Privacy & Security when requested; reopen the app afterwards.','Start output. For Extended display, arrange <b>Shuttle Extended Display</b> in macOS Displays, then drag windows onto it. Use Shuttle Audio if Mac media sound should follow it.','Stop removes the virtual display and restores the saved audio route.'])
p(b,'PAL/NTSC start with a 1024x768 desktop scaled to SD; HD starts with 1920x1080. macOS may offer other desktop sizes. The virtual desktop uses 60 Hz and is sampled into the selected video cadence. It is not a direct GPU monitor connection.')
p(b,'Extended display uses an undocumented macOS interface and may change after an OS update. Protected media may not be capturable. ScreenCaptureKit captures video here; audio uses the separate Core Audio route.')

b=page('Fit, Fill and Stretch')
table(b,['Sizing','Result'],[['Fit','Keeps the whole image and its proportions; adds borders when needed.'],['Fill','Fills without distortion by cropping the edges.'],['Stretch','Maps the whole image into the whole output frame; proportions can change.']])
h(b,'Change desktop resolutions while output runs')
steps(b,['Stop output and choose <b>Stretch</b> in Video Output, then start it.','Select the virtual/mirrored screen in macOS Displays and choose a desktop resolution. The whole current screen now fills the fixed video frame without restarting the sender.','For Fit/Fill, restart output after changing desktop resolution so their preserved-aspect geometry is recalculated.'])
p(b,'Live software tests covered all eleven requested desktop sizes into HD, PAL and NTSC output surfaces: 1920x1080, 1600x1200, 1600x900, 1344x1008, 1344x756, 1280x960, 1280x720, 1024x768, 1024x576, 960x540 and 800x600. Available choices depend on the screen.')
p(b,'A 4:3 desktop stretched to 16:9 becomes wider. This is intentional Stretch behaviour. Desktop resolution, capture resolution and physical video timing are three different settings. Choosing a larger desktop does not add 4K or 1080p50/60 Shuttle wire output.')
h(b,'Media and idle pictures')
p(b,'The same sizing choices are available for movie playback and idle pictures/movies. Restart output after changing idle sizing or media. The software accounts for PAL/NTSC pixel proportions when calculating Fit/Fill.')

b=page('Choose an idle screen')
image(b,'idle.png','Example idle picture using the original project icon, with a two-minute delay.')
steps(b,['In <b>Idle Screen</b>, choose Hold last frame, Black, Colour bars, Picture or Movie loop (silent).','Use <b>Choose media</b> for a picture/movie. Choose Fit/Fill/Stretch and a <b>Show after</b> delay.','Restart output to apply the saved choice. Keep output running; playback or scrubbing restores new editor video immediately.'])
p(b,'The default is two minutes without newly received editor frames. Delay choices are Immediately, 30 seconds, 1/2/5/10 minutes or Never. This replaces idle editor output, not a camera input-loss picture.')
p(b,'An idle movie loops silently. Keep the original movie file available at its saved location; an imported still is copied to Application Support. Missing/unreadable media falls back to black with a diagnostic.')

b=page('Sound, sync and overlays')
table(b,['Task','Audio selection'],[['Capture recording','Intensity Shuttle - Stereo Audio microphone'],['Final Cut / Mac media','Use Shuttle Audio in Shuttle Camera'],['Premiere monitoring','Intensity Shuttle - HDMI Audio in Audio Hardware'],['Movie playback','Sound from the selected movie file']])
p(b,'<b>Use Shuttle Audio</b> changes the Mac media output and saves its previous selection. Stop, helper exit or app quit restores it while the route is still the Shuttle; a later manual change is respected. Compatible device outputs can carry sound, though the Core Audio device keeps its existing HDMI Audio name. An explicit Premiere selection must be restored in Premiere.')
h(b,'Timeline audio sync')
p(b,'Negative values move sound earlier; positive values delay it. Range: -100 to +500 ms, with 10 ms stepper increments. Press Return after typing a value and compare after about a second. Reset returns to zero. This is for timeline output, not capture recording; adjustments can briefly click or skip.')
h(b,'Output monitoring aids')
bullets(b,['<b>Timecode:</b> TC HH:MM:SS:FF, or a semicolon for drop-frame. Dashes mean the editor supplied no valid timecode.','<b>L/R meters:</b> outgoing stereo levels, peak hold and clip indication.','<b>Positions:</b> six choices each for timecode and meters, with independent placement. The timecode background is translucent.','<b>Title safe 80% / Action safe 90%:</b> optional white/yellow guides. These are app guide percentages, not a broadcaster-compliance guarantee.'])
p(b,'Overlays affect the outgoing picture on compatible outputs, not the editor project/source file. Output timecode is for editors; meters/guides also work with movie playback. About and Quit are in the app menu; Help contains setup, diagnostics and driver actions.')

b=page('Troubleshooting')
table(b,['Symptom','Check'],[
['Installer error','Quit editors/camera apps and stop output. Confirm the installer heading/version; use the startup volume. Installer Log gives the actual failure.'],
['Camera missing','Enable Camera in Help > Driver Setup and approve Camera Extensions; reopen the recording app.'],
['No capture audio','Choose the separate Stereo Audio microphone, Analog RCA input and microphone permission.'],
['Screen permission loops','Quit Shuttle Camera. Remove its old Screen & System Audio Recording entry, add /Applications/Shuttle Camera.app again, enable and reopen. Ad-hoc updates can leave an old permission signature.'],
['SD screen absent in Displays','Select Extended display and Start. Use current software; PAL/NTSC now start at 1024x768. Test pattern does not create a desktop.'],
['Only part of a desktop shows','Stop, select Stretch, start again. Stretch follows live desktop size changes; restart Fit/Fill after a mode change.'],
['Editor output choppy','Match timeline/output cadence; compare A/V Output off/on. Check rendering/media load and collect diagnostics during the affected session.'],
['Purple blacks on DVI monitor','The tested Dell P2213t needs YPbPr for HDMI-to-DVI. Selectable RGB output is not implemented.'],
['Mac sound missing afterwards','Restore audio in Shuttle Camera or Sound settings; restore explicit Premiere output inside Premiere.'],
['Premiere device absent','Restart Premiere and confirm the Transmit bundle is in the legacy Plug-ins path listed on the next page.']])
p(b,'For a report, include app/macOS/editor versions, project/source frame rate, output format, connection and relevant diagnostics. Review logs for personal filenames. Every codec, 4K timeline, analogue combination and long-session latency has not been comprehensively qualified. There is no Resolve output integration or simultaneous capture/playback.')

b=page('Remove it and restore security')
steps(b,['Save work. Disable editor external output, stop playback/capture, restore sound and quit clients.','Use Help > Driver Setup > Disable Camera. Turn off both Shuttle Camera Extensions in System Settings.','Move Shuttle Camera.app from Applications to the Bin. Allow macOS to remove bundled extensions if prompted. Do not manually delete /Library/SystemExtensions.','In Finder, move only this project\'s audio driver and Premiere bundle at the paths below to the Bin. Administrator approval may be required. Restart to unload audio and finish pending removal.'])
h(b,'Installed components')
bullets(b,['App: <font name="Courier">/Applications/Shuttle Camera.app</font>','Audio: <font name="Courier">/Library/Audio/Plug-Ins/HAL/Shuttle Audio.driver</font>','Premiere: <font name="Courier">/Library/Application Support/Adobe/Common/Plug-ins/7.0/MediaCore/Shuttle/Shuttle Transmit.bundle</font>','Source, status and backups: <font name="Courier">/Library/Application Support/Shuttle Camera</font>. User settings/media are under the user\'s Library/Application Support/Shuttle Camera.'])
h(b,'Restore the development security settings')
p(b,'If developer mode was enabled, turn it off in normal Terminal:')
code(b,'sudo systemextensionsctl developer off')
p(b,'In Recovery Terminal, reenable SIP and restart. Verify with csrutil status in normal macOS. '+link('sip')+'.')
code(b,'csrutil enable')
p(b,'The ad-hoc extensions may stop working with SIP restored; this runtime configuration is not qualified. Do not reset all system extensions, because that affects unrelated software. Keep backups until normal audio and files are checked.')

styles=getSampleStyleSheet()
font_regular=Path('/System/Library/Fonts/Supplemental/Arial.ttf')
font_bold=Path('/System/Library/Fonts/Supplemental/Arial Bold.ttf')
if font_regular.exists():
 pdfmetrics.registerFont(TTFont('Guide',str(font_regular)));pdfmetrics.registerFont(TTFont('GuideBold',str(font_bold)));pdfmetrics.registerFontFamily('Guide',normal='Guide',bold='GuideBold',italic='Guide',boldItalic='GuideBold')
else: pass
font='Guide' if font_regular.exists() else 'Helvetica'
styles.add(ParagraphStyle('GuideBody',fontName=font,fontSize=10,leading=14,spaceAfter=8,textColor=colors.HexColor('#26323d')))
styles.add(ParagraphStyle('GuideHead',parent=styles['GuideBody'],fontName='GuideBold' if font_regular.exists() else 'Helvetica-Bold',fontSize=12,leading=16,spaceBefore=10,spaceAfter=6,textColor=colors.HexColor('#15293c')))
styles.add(ParagraphStyle('GuideTitle',parent=styles['GuideHead'],fontSize=24,leading=29,spaceBefore=3,spaceAfter=16))
styles.add(ParagraphStyle('GuideCaption',parent=styles['GuideBody'],fontSize=8,leading=11,textColor=colors.HexColor('#63717c'),spaceAfter=9))
styles.add(ParagraphStyle('GuideCell',parent=styles['GuideBody'],fontSize=8.7,leading=11.5,spaceAfter=0))
styles.add(ParagraphStyle('GuideCode',parent=styles['GuideBody'],fontName='Courier',fontSize=9,leading=13,backColor=colors.HexColor('#edf2f6'),borderPadding=7,spaceBefore=5,spaceAfter=11))
styles.add(ParagraphStyle('GuideNotice',parent=styles['GuideBody'],backColor=colors.HexColor('#fff2d6'),borderPadding=9,spaceBefore=9,spaceAfter=15))

def clean_pdf(t):
 t=t.replace('<b>','<b>').replace('→',' &gt; ')
 # Break long installed paths without changing their copied plain-text form in HTML/MD.
 return t.replace('/Library/','/<wbr/>Library/').replace('/Application Support/','/Application<wbr/> Support/')

def para(t,style='GuideBody'):return Paragraph(clean_pdf(t),styles[style])
def pdf_blocks(blocks):
 result=[]
 for kind,v in blocks:
  if kind=='p':result.append(para(v))
  elif kind=='h':result.append(para(v,'GuideHead'))
  elif kind=='notice':result.append(para(v,'GuideNotice'))
  elif kind in ['steps','bullets']:
   for i,t in enumerate(v):result.append(para(f'<b>{i+1}.</b> '+t if kind=='steps' else '• '+t))
  elif kind=='code':result.append(para(html.escape(v).replace('\n','<br/>'),'GuideCode'))
  elif kind=='image':
   f,caption=v;im=PILImage.open(OUT/'images'/f);w=380;result.append(Image(str(OUT/'images'/f),width=w,height=w*im.height/im.width));result.append(para(caption,'GuideCaption'))
  elif kind=='table':
   headers,rows=v;data=[[para('<b>'+html.escape(str(x))+'</b>','GuideCell') for x in headers]]+[[para(html.escape(str(x)),'GuideCell') for x in r] for r in rows]
   widths=[135, 372] if len(headers)==2 else None
   if headers[0]=='Page':widths=[45, 462]
   t=Table(data,colWidths=widths,hAlign='LEFT',repeatRows=1)
   t.setStyle(TableStyle([('BACKGROUND',(0, 0),(-1, 0),colors.HexColor('#e9eff5')),('VALIGN',(0, 0),(-1,-1),'TOP'),('LEFTPADDING',(0, 0),(-1,-1), 7),('RIGHTPADDING',(0, 0),(-1,-1), 7),('TOPPADDING',(0, 0),(-1,-1), 5),('BOTTOMPADDING',(0, 0),(-1,-1), 5),('LINEBELOW',(0, 0),(-1,-1), 0.3,colors.HexColor('#d7dfe6'))]));result.extend([t,Spacer(1, 8)])
 return result

story=[]
for i,page_data in enumerate(PAGES):
 if i:story.append(PageBreak())
 story.append(para(page_data['title'],'GuideTitle'));story.extend(pdf_blocks(page_data['blocks']))
def furniture(c,doc):
 c.saveState();c.setFillColor(colors.HexColor('#687b8b'));c.setFont(font, 8);c.drawString(44, 817,'SHUTTLE CAMERA   /   0.1.39 DEVELOPMENT BUILD');c.setStrokeColor(colors.HexColor('#d8e1e8'));c.line(44, 810, 551, 810);c.drawString(44, 25,'Installation & user guide · 18 October 2026');c.drawRightString(551, 25,str(doc.page));c.restoreState()
SimpleDocTemplate(str(OUT/'Read Me.pdf'),pagesize=A4,rightMargin=44,leftMargin=44,topMargin=53,bottomMargin=43,title='Shuttle Camera 0.1.39 — Read Me',author='Shuttle Camera Project').build(story,onFirstPage=furniture,onLaterPages=furniture)

# Single-file HTML embeds screenshots so it remains usable when copied alone.
def html_block(kind,v):
 if kind in ['p','h','notice']:
  tag={'p':'p','h':'h2','notice':'aside'}[kind];return f'<{tag}>{v}</{tag}>'
 if kind=='code':return '<pre><code>'+html.escape(v)+'</code></pre>'
 if kind in ['steps','bullets']:
  tag='ol' if kind=='steps' else 'ul';return '<'+tag+'>'+''.join('<li>'+t+'</li>' for t in v)+'</'+tag+'>'
 if kind=='image':
  file,caption=v;data=base64.b64encode((OUT/'images'/file).read_bytes()).decode();return f'<figure><img src="data:image/png;base64,{data}" alt="{html.escape(caption)}"><figcaption>{caption}</figcaption></figure>'
 if kind=='table':
  headers,rows=v;return '<table><thead><tr>'+''.join('<th>'+html.escape(str(x))+'</th>' for x in headers)+'</tr></thead><tbody>'+''.join('<tr>'+''.join('<td>'+html.escape(str(x))+'</td>' for x in row)+'</tr>' for row in rows)+'</tbody></table>'
 return ''
css='''body{margin:0;background:#edf1f5;color:#243341;font:16px/1.6 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}main{max-width:880px;margin:35px auto;background:white;padding:48px;border-radius:14px}h1{font-size:32px;line-height:1.2;color:#112a41}h2{font-size:21px;margin:26px 0 10px}a{color:#075fa9}section{padding-top:16px;margin-bottom:44px;border-top:1px solid #d9e2ea}aside{padding:18px;background:#fff2d6;border-left:4px solid #bf8023;border-radius:5px}pre{background:#edf2f6;padding:16px;overflow:auto;border-radius:5px}code{font-size:14px}li{margin-bottom:10px}table{width:100%;border-collapse:collapse;font-size:14px;margin:15px 0}th,td{text-align:left;padding:9px;border-bottom:1px solid #d8e1e8;vertical-align:top}th{background:#e9eff5}figure{margin:18px 0}img{display:block;max-width:100%;height:auto;border:1px solid #e0e5eb;border-radius:8px}figcaption{font-size:13px;color:#667585;margin-top:8px}font{overflow-wrap:anywhere}nav a{display:block;margin:5px 0}@media(max-width:650px){main{padding:22px;margin:0;border-radius:0}h1{font-size:27px}}@media print{body{background:white}main{padding:0;margin:0}section{break-before:page}a{color:inherit}}'''
contents='<h1>Shuttle Camera 0.1.39</h1><p>Illustrated installation &amp; user guide · 18 October 2026</p><nav>'+''.join(f'<a href="#page-{i+1}">{i+1}. {p["title"]}</a>' for i,p in enumerate(PAGES))+'</nav>'
for i,pg in enumerate(PAGES):contents+=f'<section id="page-{i+1}"><h1>{html.escape(pg["title"])}</h1>'+''.join(html_block(k,v) for k,v in pg['blocks'])+'</section>'
(OUT/'Read Me.html').write_text('<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Shuttle Camera 0.1.39 — Read Me</title><style>'+css+'</style><main>'+contents+'</main></html>')

def md(t):
 t=re.sub(r'<a href="([^"]+)">([^<]+)</a>',r'[\2](\1)',t);t=t.replace('<b>','**').replace('</b>','**');t=re.sub(r'<font[^>]*>','`',t).replace('</font>','`');return html.unescape(re.sub(r'<[^>]+>','',t))
lines=['# Shuttle Camera 0.1.39 — Read Me','', 'Installation & user guide · 18 October 2026','']
for pg in PAGES:
 lines+=['## '+pg['title'],'']
 for k,v in pg['blocks']:
  if k=='p':lines+=[md(v),'']
  elif k=='h':lines+=['### '+v,'']
  elif k=='notice':lines+=['> '+md(v),'']
  elif k in ['steps','bullets']:lines += [(f'{i+1}. ' if k=='steps' else '- ')+md(t) for i,t in enumerate(v)]+['']
  elif k=='code':lines+=['```sh',v,'```','']
  elif k=='image':lines += [f'![{v[1]}](images/{v[0]})','']
  elif k=='table':
   head,rows=v;lines += ['| '+' | '.join(head)+' |','| '+' | '.join(['---']*len(head))+' |']+['| '+' | '.join(map(str,r))+' |' for r in rows]+['']
(OUT/'Read Me.md').write_text('\n'.join(lines))
(OUT/'guide-content.json').write_text(json.dumps(PAGES,indent=2,ensure_ascii=False))
print(OUT)
