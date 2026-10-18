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
p(b,'<b>Shuttle Camera 0.1.31</b> · Installation and user guide · 18 October 2026')
p(b,'Capture VHS and other standard-definition sources, play movie files through HDMI, or monitor Final Cut Pro and Premiere Pro through the USB 3 Intensity Shuttle.')
b.append(('notice','<b>Development build — security changes required.</b> The installer is unsigned; its app and extensions are ad-hoc signed and not Apple-notarized. This build requires SIP to be disabled. Apple describes disabling these checks as a temporary development measure, not a normal public-release setup. Read page 2 before deciding whether to install. '+link('extension')+'.'))
h(b,'What you need')
bullets(b,['An Apple-silicon Mac. This installer requires macOS 27 or later; testing was on a Mac Studio with macOS 27.0.1. Other machines and later macOS releases are not guaranteed.','A Blackmagic Intensity Shuttle <b>USB 3</b>, a working USB 3 cable/adapter, and administrator access. The Thunderbolt Shuttle and Intel Macs are not supported by this installer.','For VHS: a working VCR, S-Video or composite video, and red/white RCA audio cables. For output: a TV or monitor connected to the Shuttle’s HDMI OUT.','A current backup and permission to change security settings. Do not change security on a managed/work Mac without its administrator’s approval.'])
h(b,'How it works')
p(b,'Shuttle Camera configures the device. Record into a separate camera app such as QuickTime Player. For movie or editor HDMI output, leave Shuttle Camera open with output started. Capture and playback share the USB interface: use one at a time.')
h(b,'Guide map')
table(b,['Page','Topic'],[['2','Security preparation'],['3','Install and enable the extensions'],['4','Capture VHS'],['5','HDMI movie playback and formats'],['6','Final Cut Pro and Premiere Pro'],['7','Sound, sync and overlays'],['8','Troubleshooting and limitations'],['9','Removal, security restoration and files']])
p(b,'Screenshots show the real 0.1.31 interface with example settings. Your selected input, output device and positions may differ. This guide is independent of Blackmagic Design, Apple and Adobe; it is not their official driver documentation.')

b=page('Security preparation')
p(b,'<b>Make this decision before installing.</b> SIP protects parts of macOS against unauthorized changes. Turning it off weakens protection across the Mac, not just this app. Developer mode relaxes extension validation. Neither setting makes downloaded software trustworthy. '+link('sip')+'; '+link('extension')+'.')
h(b,'1. Turn off SIP in Recovery — Apple silicon only')
steps(b,['Save your work and shut down the Mac. Press and hold its power button until startup options appear. Choose <b>Options → Continue</b>; select an administrator and authenticate if asked.','In Recovery, choose <b>Utilities → Terminal</b>. Enter the command below. Follow the displayed prompts for the intended startup system, then restart normally.'])
code(b,'csrutil disable')
p(b,'These are Recovery instructions; running the command in an ordinary desktop Terminal will not complete the change. '+link('recovery')+'.')
h(b,'2. Check the status in normal macOS')
code(b,'csrutil status')
p(b,'The installer checks for <b>System Integrity Protection status: disabled.</b> Do not use partial-disable flags as a substitute: this installer has not been qualified with them.')
h(b,'3. Enable extension developer mode')
p(b,'In normal macOS, open Terminal and run:')
code(b,'sudo systemextensionsctl developer on')
p(b,'Enter your Mac administrator password; Terminal does not show password characters. This is the development configuration used during testing. It is separate from SIP. '+link('extension')+'.')
h(b,'What is not required')
p(b,'These are camera system extensions and a Core Audio plug-in, not a kernel extension. This guide does not ask you to enable third-party kernel extensions, disable FileVault, disable authenticated-root protection or globally disable Gatekeeper. Follow the specific SIP procedure rather than unrelated kext instructions.')
b.append(('notice','<b>Can SIP be turned on immediately afterwards?</b> Do not assume this build will continue working with SIP enabled. That configuration has not been qualified, and its installer refuses installation/updates while SIP is enabled. Restore SIP when you finish testing or remove this build; page 9 explains how.'))

b=page('Install and enable')
h(b,'Install the package')
steps(b,['Disable external output in Premiere/Final Cut and quit those editors. Stop output and quit Shuttle Camera. Close QuickTime recording windows and other camera previews.','Open <b>Shuttle-Capture-0.1.31.pkg</b>. Install on the current macOS startup volume and enter your administrator password when macOS asks.','If Gatekeeper blocks the package, first verify that it came from a source you trust. Where macOS offers it, use <b>System Settings → Privacy &amp; Security → Open Anyway</b> for this specific package. Do not turn off Gatekeeper globally. '+link('gatekeeper')+'.','Let installation finish. Open <b>Shuttle Camera</b> from Applications. The installer preserves existing settings and backs up older Shuttle bundles.'])
h(b,'Verify a downloaded copy')
p(b,'In Terminal, type the following and drag the downloaded package into the window after the final space, then press Return:')
code(b,'shasum -a 256 ')
p(b,'Compare the result with the SHA256SUMS.txt supplied with this exact release:')
code(b,'shasum -a 256 /path/to/Shuttle-Capture-0.1.31.pkg')
p(b,'Compare all 64 checksum characters. A matching hash detects a different file; it does not replace trusting the publisher or Apple notarization.')
h(b,'First installation: enable both camera extensions')
steps(b,['In Shuttle Camera, choose <b>Help → Driver Setup → Enable Camera</b>.','Choose <b>Help → Driver Setup → Enable HDMI Output</b> if you want editor HDMI output.','If macOS asks for approval, open <b>System Settings → General → Login Items &amp; Extensions → Camera Extensions</b>. Enable <b>Shuttle Camera Extension</b> and <b>Shuttle HDMI Output Extension</b>.','Quit and reopen Shuttle Camera after activation. Restart if macOS says a restart is required. Approve camera/microphone access for the recording app when requested.'])
p(b,'An existing installation with both extensions already enabled does not need reactivation for the 0.1.31 interface update. First-time installation may refresh Core Audio and briefly interrupt sound; restart if the audio devices are missing.')

b=page('Capture VHS')
image(b,'capture.png','Capture panel. This example uses PAL composite video and 768 × 576 square-pixel output; select S-Video when using that cable.')
steps(b,['Connect VCR video OUT to the matching Shuttle input. Connect red/white audio OUT to the Shuttle’s analog RCA inputs. Connect the Shuttle to USB 3 and press Play on the VCR.','Choose <b>PAL</b> or <b>NTSC</b>, the correct <b>Video input</b>, and <b>Analog RCA</b>. Choose a resolution and video-loss behavior, then click <b>Apply</b>. Close capture previews before changing settings.','In QuickTime Player, choose <b>File → New Movie Recording</b>. Select the Intensity Shuttle camera and <b>Intensity Shuttle — Stereo Audio</b> as the microphone. Check both picture and audio meter before recording.'])
p(b,'PAL: native 720 × 576 or square-pixel 768 × 576. NTSC: native 720 × 480 or square-pixel 640 × 480. Both also offer 1280 × 960 and 1440 × 1080 (4:3). Larger sizes are scaled, with no extra tape detail. PAL 50 fps / NTSC 59.94 fps capture uses bob deinterlacing of the source fields.')
p(b,'<b>On video loss:</b> Hold last frame repeats the last picture; Black substitutes black. Dropout handling preserves the timing rather than shortening the recording, but it cannot recover a damaged tape signal. Check a short recorded clip for sound and sync before a long transfer.')

b=page('Play a movie over HDMI')
image(b,'movie.png','Movie file controls with illustrative settings. Example movie.mov is a placeholder; no movie was opened or played to make this screenshot.')
steps(b,['Connect the display directly to the Shuttle’s <b>HDMI OUT</b>. Close all Shuttle camera previews.','Choose <b>Video Output → Source → Movie file</b>, then <b>Choose movie…</b>. Select the HDMI format.','Enable <b>Loop</b> to repeat the movie. Click <b>Start output</b>; use <b>Stop</b> when finished. Movie audio travels through the Shuttle; Use HDMI audio is not needed for the movie file’s own sound.'])
table(b,['HDMI format','Picture format / cadence'],[['PAL · 576i50','720 × 576; 50 fields/s'],['NTSC · 480i59.94','720 × 486 output raster; 59.94 fields/s'],['1080i50 / 1080i59.94','1920 × 1080; 50 / 59.94 fields/s'],['1080p25 / 1080p29.97','1920 × 1080; 25 / 29.97 frames/s']])
p(b,'A TV may round 59.94 to “60” and 29.97 to “30”. Use Test pattern for a short display/cable test. Capture resolution and HDMI output format are separate settings. Capture cannot run at the same time as USB playback.')

b=page('Final Cut Pro and Premiere Pro')
h(b,'Final Cut Pro — tested with 11.2')
steps(b,['Close Shuttle capture previews. In Shuttle Camera → Video Output choose <b>Final Cut Pro</b> and a format matching the timeline, for example <b>1080p25</b> for 25 fps.','Click <b>Use HDMI audio</b>, then <b>Start Final Cut</b>. Wait for <b>Ready for Final Cut</b>. Keep Shuttle Camera open.','In Final Cut, choose <b>Settings → Playback → A/V Output → Intensity Shuttle — HDMI Output</b>. Enable <b>Window → A/V Output</b>, then scrub and play.','When finished, turn <b>Window → A/V Output</b> off first; then click Stop in Shuttle Camera. Restore audio if needed. Turning A/V Output off alone does not restore the Mac’s normal sound route.'])
h(b,'Premiere Pro — tested with 25.2.3 (2025)')
steps(b,['In Shuttle Camera → Video Output choose <b>Premiere Pro</b> and the matching HDMI format. Click <b>Start Premiere</b> and wait for <b>Ready for Premiere</b>.','In Premiere, choose <b>Settings/Preferences → Playback</b>. Enable <b>Mercury Transmit</b> and tick the video stream for <b>Intensity Shuttle — HDMI Output</b>. This is separate from the original Blackmagic Playback entry.','For sound, choose <b>Intensity Shuttle — HDMI Audio</b> in Premiere’s <b>Audio Hardware → Default Output</b>. The Mercury Transmit plug-in is video-only; its empty Transmit audio-stream column is expected.','Play or scrub the sequence. Leave Shuttle Camera running. If output disappears when Premiere is in the background, check Premiere’s Disable video output when in the background setting.','Disable Mercury Transmit before stopping output. If you explicitly selected the HDMI audio device in Premiere, select your normal output in Premiere Audio Hardware afterwards.'])
h(b,'If the output device is missing')
p(b,'Restart Premiere after installing its plug-in. Final Cut publishes the device after the matching USB sender is ready. Start with matching timeline/output rates; conversion between arbitrary frame rates has not been qualified. The current installer places Premiere’s transmitter in the legacy <b>Plug-ins</b> folder used by the tested Premiere 2025 installation, not the differently named Plugins folder.')
p(b,'Close one editor’s external output before using another. The same physical Shuttle cannot serve two simultaneous playback sessions.')

b=page('Sound, sync and overlays')
h(b,'Choose the right audio device')
table(b,['Task','Audio selection'],[['VHS recording','Intensity Shuttle — Stereo Audio as the recording app’s microphone'],['Final Cut HDMI monitoring','Use HDMI audio in Shuttle Camera before starting editor output'],['Premiere HDMI monitoring','Intensity Shuttle — HDMI Audio in Premiere Audio Hardware'],['Movie file output','Sound comes from the selected movie file']])
p(b,'<b>Use HDMI audio</b> changes the Mac’s default media output and saves its previous choice. Stop, helper exit or app quit restores that choice only if the route is still Shuttle HDMI. A later manual change is respected. This does not restore an explicit per-application output selected inside Premiere; change that in Premiere itself.')
h(b,'Adjust audio sync')
p(b,'Use <b>Audio sync</b> in Video Output while timeline monitoring. Negative values move sound earlier; positive values delay it. Range: −100 to +500 ms. If sound is slightly late, try −20 ms, press Return, and compare again. Wait about a second between adjustments. The stepper changes by 10 ms; Reset returns to zero. A live adjustment can briefly click or skip. This setting is for timeline HDMI sound, not capture recording.')
h(b,'HDMI overlays')
bullets(b,['<b>Timecode:</b> TC HH:MM:SS:FF from the editor, with a DF marker for drop-frame. Dashes mean valid timecode was not supplied. It is not an invented elapsed counter.','<b>L/R audio meters:</b> independent stereo levels with peak hold and clip indication. The meters show sound sent to HDMI.','<b>Positions:</b> top left, top right, bottom left, bottom right, top centre or bottom centre. Timecode and meters have separate positions.','<b>Title safe (80%) / Action safe (90%):</b> optional white/yellow guides. These are the app’s guide percentages, not a guarantee of compliance with a broadcaster’s delivery specification.'])
p(b,'Overlays affect the outgoing HDMI picture only; they do not burn into the source file or editor project. Settings are saved and update live. Timecode is available for editor output; meters and safe guides also work with movie playback.')
h(b,'Menus')
p(b,'<b>Shuttle Camera → About</b> shows the version; <b>Quit (⌘Q)</b> closes the app. <b>Help → Output Setup</b> gives source-specific instructions. <b>Help → Diagnostics</b> opens the technical log. <b>Help → Driver Setup</b> contains the extension enable/disable actions.')

b=page('Troubleshooting and limits')
table(b,['Problem','What to check'],[
['Installer fails','Quit both editors and Shuttle Camera, close capture previews, check SIP status, and use the current startup volume. Installer → Window → Installer Log shows the precise reason.'],
['Camera missing','Use Help → Driver Setup → Enable Camera. Approve Camera Extensions in System Settings, then reopen Shuttle Camera and the recording app.'],
['No capture sound','Use the separate Stereo Audio microphone, Analog RCA for VCR red/white cables, and check app microphone permission.'],
['Ready never appears','Close capture previews, check USB 3 cable/adapter and power, reconnect the Shuttle after stopping clients, then retry. Read Help → Diagnostics.'],
['Premiere device missing','Restart Premiere; confirm the Shuttle transmitter exists in the Plug-ins path on page 9. Do not select Blackmagic Playback as a substitute for this plug-in.'],
['Picture, no HDMI sound','Check Premiere Audio Hardware or Final Cut’s Use HDMI audio route. TV speakers must be enabled; HDMI-to-DVI connections do not provide TV audio.'],
['Purple blacks / wrong colours','On the tested Dell P2213t with HDMI-to-DVI, set its Input Color Format to YPbPr. RGB selection in this app is not implemented. Direct HDMI to the tested TV worked.'],
['Mac sound missing afterwards','Click Restore audio or choose normal speakers in Sound settings. Also undo any explicit HDMI output selection inside Premiere.'],
['Editor freezes / viewer stops','Disable external output, then stop Shuttle output. Relaunch only after saving work. Report the format, editor version and Diagnostics log; do not keep toggling output during a hung session.']])
h(b,'Current limitations')
p(b,'This build is Apple silicon only. Capture is standard-definition; S-Video/composite VHS capture is the main tested workflow. Listed Component/HDMI capture options do not imply HD capture support. There is no DaVinci Resolve output integration, selectable RGB HDMI mode, simultaneous capture/playback or qualified 1080p50/60 output.')
p(b,'Testing covered the listed PAL/NTSC/1080 modes on one Mac Studio setup. It is not proof of compatibility with every USB controller, display, movie codec, editor update or tape. Very long sessions, exact measured physical A/V latency and fresh installs on other Macs have not been comprehensively qualified.')
p(b,'For a useful report, include the app/macOS/editor versions, source and HDMI format, connection type, whether the camera is in use, and relevant Diagnostics/Installer Log lines. Review logs for private file names before sharing them.')

b=page('Remove it and restore security')
h(b,'Remove the development components')
steps(b,['Save your work. Disable editor external output, quit the editors, stop Shuttle output and restore normal audio. Close recording/camera previews.','In Shuttle Camera, use <b>Help → Driver Setup → Disable Camera</b>. In System Settings → Camera Extensions, turn off both Shuttle extensions.','Move <b>Shuttle Camera.app</b> from Applications to the Bin using Finder. Allow macOS to remove its bundled extensions if prompted. Do not manually delete files from /Library/SystemExtensions.','In Finder → Go → Go to Folder, visit the HAL path below and move only <b>Shuttle Audio.driver</b> to the Bin. Visit the Premiere path and move only <b>Shuttle Transmit.bundle</b> to the Bin. Administrator approval may be required.','Restart to unload audio and finish any pending extension removal. Check that other audio devices work normally. Do not use systemextensionsctl reset; it would affect unrelated extensions.'])
h(b,'Turn extension developer mode off in normal macOS')
code(b,'sudo systemextensionsctl developer off')
h(b,'Turn SIP back on in Recovery')
p(b,'Boot to Recovery as on page 2, choose Utilities → Terminal, run the command below, then restart normally. Verify with csrutil status in the desktop Terminal. If you separately changed Startup Security policies, consult Apple’s Recovery guidance to restore the appropriate policy for your startup system. '+link('sip')+'.')
code(b,'csrutil enable')
p(b,'The ad-hoc development extensions may stop working after restoring SIP; do not treat this as a supported way to keep using this build. Retain backups until you have checked your files and normal audio. Accessing installer backups may require administrator rights.')
h(b,'Installed files and source')
bullets(b,['App: <font name="Courier">/Applications/Shuttle Camera.app</font>','Audio: <font name="Courier">/Library/Audio/Plug-Ins/HAL/Shuttle Audio.driver</font>','Premiere: <font name="Courier">/Library/Application Support/Adobe/Common/Plug-ins/7.0/MediaCore/Shuttle/Shuttle Transmit.bundle</font>','Source archive, licences, installation status and backups: <font name="Courier">/Library/Application Support/Shuttle Camera/</font>'])
p(b,'Project source includes GPL/LGPL components; consult COPYING and component licences in Source.zip. Adobe’s SDK must be obtained separately for rebuilding the Premiere adapter. The new original SVHS project artwork was generated from a text-only prompt without the previous icon as an input; it is included under the project GPL-2.0-or-later terms. See ICON-NOTE.md in the source resources.')

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
   widths=[135,372] if len(headers)==2 else None
   if headers[0]=='Page':widths=[45,462]
   t=Table(data,colWidths=widths,hAlign='LEFT',repeatRows=1)
   t.setStyle(TableStyle([('BACKGROUND',(0,0),(-1,0),colors.HexColor('#e9eff5')),('VALIGN',(0,0),(-1,-1),'TOP'),('LEFTPADDING',(0,0),(-1,-1),7),('RIGHTPADDING',(0,0),(-1,-1),7),('TOPPADDING',(0,0),(-1,-1),5),('BOTTOMPADDING',(0,0),(-1,-1),5),('LINEBELOW',(0,0),(-1,-1),0.3,colors.HexColor('#d7dfe6'))]));result.extend([t,Spacer(1,8)])
 return result

story=[]
for i,page_data in enumerate(PAGES):
 if i:story.append(PageBreak())
 story.append(para(page_data['title'],'GuideTitle'));story.extend(pdf_blocks(page_data['blocks']))
def furniture(c,doc):
 c.saveState();c.setFillColor(colors.HexColor('#687b8b'));c.setFont(font,8);c.drawString(44,817,'SHUTTLE CAMERA   /   0.1.31 DEVELOPMENT BUILD');c.setStrokeColor(colors.HexColor('#d8e1e8'));c.line(44,810,551,810);c.drawString(44,25,'Installation & user guide · 18 October 2026');c.drawRightString(551,25,str(doc.page));c.restoreState()
SimpleDocTemplate(str(OUT/'Read Me.pdf'),pagesize=A4,rightMargin=44,leftMargin=44,topMargin=53,bottomMargin=43,title='Shuttle Camera 0.1.31 — Read Me',author='Shuttle Camera Project').build(story,onFirstPage=furniture,onLaterPages=furniture)

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
contents='<h1>Shuttle Camera 0.1.31</h1><p>Illustrated installation &amp; user guide · 18 October 2026</p><nav>'+''.join(f'<a href="#page-{i+1}">{i+1}. {p["title"]}</a>' for i,p in enumerate(PAGES))+'</nav>'
for i,pg in enumerate(PAGES):contents+=f'<section id="page-{i+1}"><h1>{html.escape(pg["title"])}</h1>'+''.join(html_block(k,v) for k,v in pg['blocks'])+'</section>'
(OUT/'Read Me.html').write_text('<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Shuttle Camera 0.1.31 — Read Me</title><style>'+css+'</style><main>'+contents+'</main></html>')

def md(t):
 t=re.sub(r'<a href="([^"]+)">([^<]+)</a>',r'[\2](\1)',t);t=t.replace('<b>','**').replace('</b>','**');t=re.sub(r'<font[^>]*>','`',t).replace('</font>','`');return html.unescape(re.sub(r'<[^>]+>','',t))
lines=['# Shuttle Camera 0.1.31 — Read Me','', 'Installation & user guide · 18 October 2026','']
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
