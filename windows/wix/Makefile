ARCH=x64

VERSION=0.00
SRCDIR=.\prefix
OUTDIR=.\output
OBJDIR=$(OUTDIR)\.obj.$(ARCH)
WEBSRCDIR=$(SRCDIR)\share\transmission\web
TRQMSRCDIR=$(SRCDIR)\share\transmission\translations
THIRDPARTYIDIR=C:\Qt\3rd-party-msvc64
QTDIR=C:\Qt\5.6.0-msvc64
QTQMSRCDIR=$(QTDIR)\translations

HEAT_ARGS=-nologo -sfrag -ag -srd -indent 2
CANDLE_ARGS=-nologo -pedantic -ext WixUIExtension -ext WixUtilExtension -arch "$(ARCH)"
LIGHT_ARGS=-nologo -pedantic -ext WixUIExtension -ext WixUtilExtension -sw1076

HEAT_SRCS=$(OBJDIR)\WebUi.wxs $(OBJDIR)\QtClientTranslations.wxs $(OBJDIR)\QtTranslations.wxs
OBJS=$(OBJDIR)\Transmission.wixobj $(OBJDIR)\CliTools.wixobj $(OBJDIR)\CommonLibs.wixobj $(OBJDIR)\Daemon.wixobj $(OBJDIR)\QtClient.wixobj $(OBJDIR)\WebUi.wixobj $(OBJDIR)\QtClientTranslations.wixobj $(OBJDIR)\QtTranslations.wixobj

all: $(OUTDIR)\transmission-$(VERSION)-$(ARCH).msi

$(OUTDIR)\transmission-$(VERSION)-$(ARCH).msi $(OUTDIR)\transmission-$(VERSION)-$(ARCH).wixpdb: $(OBJS)
	@if not exist $(OUTDIR) mkdir $(OUTDIR)
	light $(LIGHT_ARGS) -out $(OUTDIR)\transmission-$(VERSION)-$(ARCH).msi $(OBJS)

$(OBJDIR)\Transmission.wixobj: Transmission.wxs TransmissionConfig.wxi $(OBJDIR)\gplv2.rtf
	@if not exist $(OBJDIR) mkdir $(OBJDIR)
	candle $(CANDLE_ARGS) "-dSrcDir=$(SRCDIR)" "-dThirdPartyDir=$(THIRDPARTYIDIR)" "-dQtDir=$(QTDIR)" -dLicenseFile=$(OBJDIR)\gplv2.rtf Transmission.wxs -out $(OBJDIR)\Transmission.wixobj

$(OBJDIR)\CliTools.wixobj: components\CliTools.wxs
	@if not exist $(OBJDIR) mkdir $(OBJDIR)
	candle $(CANDLE_ARGS) "-dSrcDir=$(SRCDIR)" components\CliTools.wxs -out $(OBJDIR)\CliTools.wixobj

$(OBJDIR)\CommonLibs.wixobj: components\CommonLibs.wxs
	@if not exist $(OBJDIR) mkdir $(OBJDIR)
	candle $(CANDLE_ARGS) "-dSrcDir=$(SRCDIR)" "-dThirdPartyDir=$(THIRDPARTYIDIR)" components\CommonLibs.wxs -out $(OBJDIR)\CommonLibs.wixobj

$(OBJDIR)\Daemon.wixobj: components\Daemon.wxs
	@if not exist $(OBJDIR) mkdir $(OBJDIR)
	candle $(CANDLE_ARGS) "-dSrcDir=$(SRCDIR)" components\Daemon.wxs -out $(OBJDIR)\Daemon.wixobj

$(OBJDIR)\QtClient.wixobj: components\QtClient.wxs
	@if not exist $(OBJDIR) mkdir $(OBJDIR)
	candle $(CANDLE_ARGS) "-dSrcDir=$(SRCDIR)" "-dThirdPartyDir=$(THIRDPARTYIDIR)" "-dQtDir=$(QTDIR)" components\QtClient.wxs -out $(OBJDIR)\QtClient.wixobj

$(OBJDIR)\WebUi.wixobj: $(OBJDIR)\WebUi.wxs
	@if not exist $(OBJDIR) mkdir $(OBJDIR)
	candle $(CANDLE_ARGS) "-dWebSrcDir=$(WEBSRCDIR)" $(OBJDIR)\WebUi.wxs -out $(OBJDIR)\WebUi.wixobj

$(OBJDIR)\QtClientTranslations.wixobj: $(OBJDIR)\QtClientTranslations.wxs
	@if not exist $(OBJDIR) mkdir $(OBJDIR)
	candle $(CANDLE_ARGS) "-dTrQmSrcDir=$(TRQMSRCDIR)" $(OBJDIR)\QtClientTranslations.wxs -out $(OBJDIR)\QtClientTranslations.wixobj

$(OBJDIR)\QtTranslations.wixobj: $(OBJDIR)\QtTranslations.wxs
	@if not exist $(OBJDIR) mkdir $(OBJDIR)
	candle $(CANDLE_ARGS) "-dQtQmSrcDir=$(QTQMSRCDIR)" $(OBJDIR)\QtTranslations.wxs -out $(OBJDIR)\QtTranslations.wixobj

$(OBJDIR)\WebUi.wxs:
	@if not exist $(OBJDIR) mkdir $(OBJDIR)
	heat dir "$(WEBSRCDIR)" $(HEAT_ARGS) -cg WebUiComponents -dr WEBINSTALLDIR -var var.WebSrcDir -out $(OBJDIR)\WebUi.wxs

$(OBJDIR)\QtClientTranslations.wxs:
	@if not exist $(OBJDIR) mkdir $(OBJDIR)
	heat dir "$(TRQMSRCDIR)" $(HEAT_ARGS) -cg QtClientTranslationsComponents -dr QMINSTALLDIR -var var.TrQmSrcDir -out $(OBJDIR)\QtClientTranslations.wxs

$(OBJDIR)\QtTranslations.wxs: QtTranslations.xsl
	@if not exist $(OBJDIR) mkdir $(OBJDIR)
	heat dir "$(QTQMSRCDIR)" $(HEAT_ARGS) -cg QtTranslationsComponents -dr QMINSTALLDIR -var var.QtQmSrcDir -t QtTranslations.xsl -out $(OBJDIR)\QtTranslations.wxs

$(OBJDIR)\gplv2.rtf:
	@if not exist $(OBJDIR) mkdir $(OBJDIR)
	powershell -Command "[void][System.Reflection.Assembly]::LoadWithPartialName(\"System.Windows.Forms\"); $$a = Invoke-WebRequest http://www.gnu.org/licenses/gpl-2.0.txt -UseBasicParsing; $$b = New-Object -TypeName System.Windows.Forms.RichTextBox; $$b.Text = $$a.Content; $$b.SelectAll(); $$b.SelectionFont = New-Object -TypeName System.Drawing.Font(\"Consolas\", 7.5); $$b.Rtf | Set-Content $(OBJDIR)\gplv2.rtf"

clean:
	del $(HEAT_SRCS) $(OBJDIR)\gplv2.rtf $(OBJS) $(OUTDIR)\transmission-$(ARCH).wixpdb $(OUTDIR)\transmission-$(ARCH).msi
	rmdir /S /Q "$(OBJDIR)"
	rmdir /S /Q "$(OUTDIR)"
