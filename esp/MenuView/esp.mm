#import "esp.h"
#import "mahoa.h"
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h> 
#include <sys/mman.h>
#include <string>
#include <vector>
#include <cmath>

uint64_t Moudule_Base = -1;

// --- ESP Config ---
static bool isBox = YES;
static bool isBone = YES;
static bool isHealth = YES;
static bool isName = YES;
static bool isDis = YES;

// --- Aimbot Config ---
static bool isAimbot = NO;
static float aimFov = 150.0f; // Bán kính vòng tròn FOV
static float aimDistance = 200.0f; // Khoảng cách aim mặc định

@interface CustomSwitch : UIControl
@property (nonatomic, assign, getter=isOn) BOOL on;
@end

@interface CustomSlider : UIView
@property (nonatomic, assign) float value;
@property (nonatomic, assign) float minValue;
@property (nonatomic, assign) float maxValue;
@property (nonatomic, copy) void (^onChange)(float value);
@end

@implementation CustomSlider {
    UIView *_track;
    UIView *_fill;
    UIView *_thumb;
}
- (instancetype)initWithFrame:(CGRect)frame min:(float)min max:(float)max value:(float)val {
    self = [super initWithFrame:frame];
    if (self) {
        _minValue = min;
        _maxValue = max;
        _value = val;
        self.userInteractionEnabled = YES;
        
        _track = [[UIView alloc] initWithFrame:CGRectMake(0, frame.size.height/2 - 2, frame.size.width, 4)];
        _track.backgroundColor = [UIColor colorWithWhite:0.3 alpha:1.0];
        _track.layer.cornerRadius = 2;
        [self addSubview:_track];
        
        float ratio = (val - min) / (max - min);
        _fill = [[UIView alloc] initWithFrame:CGRectMake(0, frame.size.height/2 - 2, frame.size.width * ratio, 4)];
        _fill.backgroundColor = [UIColor greenColor];
        _fill.layer.cornerRadius = 2;
        [self addSubview:_fill];
        
        _thumb = [[UIView alloc] initWithFrame:CGRectMake(frame.size.width * ratio - 10, frame.size.height/2 - 10, 20, 20)];
        _thumb.backgroundColor = [UIColor whiteColor];
        _thumb.layer.cornerRadius = 10;
        [self addSubview:_thumb];
        
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [self addGestureRecognizer:pan];
    }
    return self;
}
- (void)handlePan:(UIPanGestureRecognizer *)g {
    CGPoint pt = [g locationInView:self];
    float ratio = MAX(0, MIN(1, pt.x / self.bounds.size.width));
    _value = _minValue + ratio * (_maxValue - _minValue);
    [self updateUI];
    if (_onChange) _onChange(_value);
}
- (void)updateUI {
    float ratio = (_value - _minValue) / (_maxValue - _minValue);
    _fill.frame = CGRectMake(0, self.bounds.size.height/2 - 2, self.bounds.size.width * ratio, 4);
    _thumb.center = CGPointMake(self.bounds.size.width * ratio, self.bounds.size.height/2);
}
@end



@implementation CustomSwitch { UIView *_thumb; }
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        _thumb = [[UIView alloc] initWithFrame:CGRectMake(2, 2, 22, 22)];
        _thumb.backgroundColor = [UIColor colorWithWhite:0.75 alpha:1.0];
        _thumb.layer.cornerRadius = 11;
        [self addSubview:_thumb];
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggle)];
        [self addGestureRecognizer:tap];
    }
    return self;
}
- (void)drawRect:(CGRect)rect {
    CGContextRef context = UIGraphicsGetCurrentContext();
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:self.bounds.size.height/2];
    CGContextSetFillColorWithColor(context, (self.isOn ? [UIColor colorWithRed:0.0 green:0.8 blue:0.0 alpha:1.0] : [UIColor colorWithWhite:0.15 alpha:1.0]).CGColor);
    [path fill];
}
- (void)setOn:(BOOL)on {
    if (_on != on) { _on = on; [self setNeedsDisplay]; [self updateThumbPosition]; }
}
- (void)toggle {
    self.on = !self.on;
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}
- (void)updateThumbPosition {
    [UIView animateWithDuration:0.2 animations:^{
        CGRect frame = self->_thumb.frame;
        frame.origin.x = self.isOn ? self.bounds.size.width - frame.size.width - 2 : 2;
        self->_thumb.frame = frame;
        self->_thumb.backgroundColor = self.isOn ? UIColor.whiteColor : [UIColor colorWithWhite:0.75 alpha:1.0];
    }];
}
@end

@interface MenuView ()
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, strong) NSMutableArray<CALayer *> *drawingLayers;
- (void)renderESPToLayers:(NSMutableArray<CALayer *> *)layers;
@end

@implementation MenuView {
    UIView *menuContainer;
    UIView *floatingButton;
    CGPoint _initialTouchPoint;
    
    // Tab Views
    UIView *mainTabContainer;
    UIView *aimTabContainer;
    UIView *settingTabContainer;
    UIView *debugTabContainer;
    UITextView *debugLogView;
    UILabel *scanBtnLabel;
    BOOL debugScanEnabled;
    NSTimer *debugScanTimer;

    UIView *previewView;
    UIView *previewContentContainer;
    
    UILabel *previewNameLabel;
    UILabel *previewDistLabel;
    UIView *healthBarContainer;
    UIView *boxContainer;
    UIView *skeletonContainer;
    
    float previewScale;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = YES;
        self.backgroundColor = [UIColor clearColor];
        self.drawingLayers = [NSMutableArray array];
        
        [self SetUpBase];
        self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(updateFrame)];
        [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];

        [self setupFloatingButton];
        [self setupMenuUI];
        [self layoutSubviews];
    }
    return self;
}

- (void)setupFloatingButton {
    floatingButton = [[UIView alloc] initWithFrame:CGRectMake(50, 50, 50, 50)];
    floatingButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.8 blue:0.0 alpha:1.0];
    floatingButton.layer.cornerRadius = 25;
    floatingButton.layer.borderWidth = 2;
    floatingButton.layer.borderColor = [UIColor whiteColor].CGColor;
    floatingButton.clipsToBounds = YES;
    
    UILabel *iconLabel = [[UILabel alloc] initWithFrame:floatingButton.bounds];
    iconLabel.text = @"M";
    iconLabel.textColor = [UIColor whiteColor];
    iconLabel.textAlignment = NSTextAlignmentCenter;
    iconLabel.font = [UIFont boldSystemFontOfSize:20];
    [floatingButton addSubview:iconLabel];
    
    UITapGestureRecognizer *openTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(showMenu)];
    [floatingButton addGestureRecognizer:openTap];
    
    UIPanGestureRecognizer *iconPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [floatingButton addGestureRecognizer:iconPan];
    
    [self addSubview:floatingButton];
}

- (void)addFeatureToView:(UIView *)view withTitle:(NSString *)title atY:(CGFloat)y initialValue:(BOOL)isOn andAction:(SEL)action {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(15, y, 150, 26)];
    label.text = title;
    label.textColor = [UIColor whiteColor];
    label.font = [UIFont systemFontOfSize:13];
    [view addSubview:label];
    
    CustomSwitch *customSwitch = [[CustomSwitch alloc] initWithFrame:CGRectMake(240, y, 52, 26)];
    customSwitch.on = isOn;
    [customSwitch addTarget:self action:action forControlEvents:UIControlEventValueChanged];
    [view addSubview:customSwitch];
}

- (void)setupMenuUI {
    CGFloat menuWidth = 550;
    CGFloat menuHeight = 320;
    
    menuContainer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, menuWidth, menuHeight)];
    menuContainer.backgroundColor = [UIColor colorWithRed:0.05 green:0.05 blue:0.05 alpha:0.95];
    menuContainer.layer.cornerRadius = 15;
    menuContainer.layer.borderColor = [UIColor colorWithRed:0.2 green:0.2 blue:0.2 alpha:1.0].CGColor;
    menuContainer.layer.borderWidth = 2;
    menuContainer.clipsToBounds = YES;
    menuContainer.userInteractionEnabled = YES;
    menuContainer.hidden = YES;
    [self addSubview:menuContainer];
    
    // Header
    UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, menuWidth, 40)];
    headerView.backgroundColor = [UIColor clearColor];
    [menuContainer addSubview:headerView];
    
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(160, 5, 200, 30)];
    titleLabel.text = @"MENU TIPA";
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.font = [UIFont fontWithName:@"HelveticaNeue-Bold" size:22];
    [headerView addSubview:titleLabel];
    
    UILabel *subTitle = [[UILabel alloc] initWithFrame:CGRectMake(350, 12, 150, 20)];
    subTitle.text = @"Cheat by LDVQuang";
    subTitle.textColor = [UIColor lightGrayColor];
    subTitle.font = [UIFont systemFontOfSize:10];
    [headerView addSubview:subTitle];
    
    NSArray *colors = @[[UIColor greenColor], [UIColor yellowColor], [UIColor redColor]];
    for (int i = 0; i < 3; i++) {
        UIView *circle = [[UIView alloc] initWithFrame:CGRectMake(menuWidth - 80 + (i * 25), 10, 18, 18)];
        circle.backgroundColor = colors[i];
        circle.layer.cornerRadius = 9;
        
        UILabel *btnIcon = [[UILabel alloc] initWithFrame:circle.bounds];
        btnIcon.textAlignment = NSTextAlignmentCenter;
        btnIcon.font = [UIFont boldSystemFontOfSize:12];
        btnIcon.textColor = [UIColor blackColor];
        
        if (i == 0) btnIcon.text = @"□";
        if (i == 1) btnIcon.text = @"-";
        if (i == 2) {
            btnIcon.text = @"X";
            UITapGestureRecognizer *closeTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(hideMenu)];
            [circle addGestureRecognizer:closeTap];
        }
        [circle addSubview:btnIcon];
        [headerView addSubview:circle];
    }
    
    UIPanGestureRecognizer *menuPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    menuPan.cancelsTouchesInView = NO;
    [headerView addGestureRecognizer:menuPan];
    
    // Sidebar Buttons
    UIView *sidebar = [[UIView alloc] initWithFrame:CGRectMake(465, 50, 75, 250)];
    sidebar.backgroundColor = [UIColor colorWithWhite:0.8 alpha:1.0];
    sidebar.layer.cornerRadius = 10;
    sidebar.userInteractionEnabled = YES;
    [menuContainer addSubview:sidebar];
    
    NSArray *tabs = @[@"Main", @"AIM", @"Setting", @"Debug"];
    for (int i = 0; i < tabs.count; i++) {
        UIView *tabBtn = [[UIView alloc] initWithFrame:CGRectMake(5, 10 + (i * 50), 65, 35)];
        tabBtn.backgroundColor = (i == 0) ? [UIColor colorWithRed:0.2 green:0.2 blue:0.2 alpha:1.0] : [UIColor colorWithRed:0.3 green:0.3 blue:0.3 alpha:1.0];
        tabBtn.layer.cornerRadius = 17.5;
        tabBtn.tag = i;
        tabBtn.userInteractionEnabled = YES;
        
        UILabel *lbl = [[UILabel alloc] initWithFrame:tabBtn.bounds];
        lbl.text = tabs[i];
        lbl.textColor = [UIColor whiteColor];
        lbl.textAlignment = NSTextAlignmentCenter;
        lbl.font = [UIFont boldSystemFontOfSize:11];
        lbl.userInteractionEnabled = NO;
        [tabBtn addSubview:lbl];
        
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tabTapped:)];
        [tabBtn addGestureRecognizer:tap];
        [sidebar addSubview:tabBtn];
    }

    // --- MAIN TAB (ESP) ---
    mainTabContainer = [[UIView alloc] initWithFrame:CGRectMake(15, 50, 440, 250)];
    mainTabContainer.backgroundColor = [UIColor clearColor];
    [menuContainer addSubview:mainTabContainer];

    // Preview Section (Left)
    UIView *previewBorder = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 130, 250)];
    previewBorder.layer.borderColor = [UIColor whiteColor].CGColor;
    previewBorder.layer.borderWidth = 1;
    previewBorder.layer.cornerRadius = 10;
    [mainTabContainer addSubview:previewBorder];
    
    UILabel *pvTitle = [[UILabel alloc] initWithFrame:CGRectMake(0, 5, 130, 20)];
    pvTitle.text = @"Preview";
    pvTitle.textColor = [UIColor whiteColor];
    pvTitle.textAlignment = NSTextAlignmentCenter;
    pvTitle.font = [UIFont boldSystemFontOfSize:14];
    [previewBorder addSubview:pvTitle];
    
    UIView *line = [[UIView alloc] initWithFrame:CGRectMake(10, 28, 110, 1)];
    line.backgroundColor = [UIColor whiteColor];
    [previewBorder addSubview:line];
    
    previewView = [[UIView alloc] initWithFrame:CGRectMake(0, 30, 130, 220)];
    previewView.backgroundColor = [UIColor blackColor];
    previewView.clipsToBounds = YES;
    [previewBorder addSubview:previewView];
    
    previewContentContainer = [[UIView alloc] initWithFrame:previewView.bounds];
    [previewView addSubview:previewContentContainer];
    
    [self drawPreviewElements];
    [self updatePreviewVisibility];

    // Feature Box (Right)
    UIView *featureBox = [[UIView alloc] initWithFrame:CGRectMake(140, 0, 300, 250)];
    featureBox.layer.borderColor = [UIColor whiteColor].CGColor;
    featureBox.layer.borderWidth = 1;
    featureBox.layer.cornerRadius = 10;
    featureBox.backgroundColor = [UIColor blackColor];
    featureBox.userInteractionEnabled = YES;
    [mainTabContainer addSubview:featureBox];
    
    UILabel *ftTitle = [[UILabel alloc] initWithFrame:CGRectMake(15, 10, 200, 20)];
    ftTitle.text = @"ESP Feature";
    ftTitle.textColor = [UIColor whiteColor];
    ftTitle.font = [UIFont boldSystemFontOfSize:16];
    [featureBox addSubview:ftTitle];
    
    UIView *ftLine = [[UIView alloc] initWithFrame:CGRectMake(15, 35, 270, 1)];
    ftLine.backgroundColor = [UIColor whiteColor];
    [featureBox addSubview:ftLine];
    
    [self addFeatureToView:featureBox withTitle:@"Box" atY:45 initialValue:isBox andAction:@selector(toggleBox:)];
    [self addFeatureToView:featureBox withTitle:@"Bone" atY:80 initialValue:isBone andAction:@selector(toggleBone:)];
    [self addFeatureToView:featureBox withTitle:@"Health" atY:115 initialValue:isHealth andAction:@selector(toggleHealth:)];
    [self addFeatureToView:featureBox withTitle:@"Name" atY:150 initialValue:isName andAction:@selector(toggleName:)];
    [self addFeatureToView:featureBox withTitle:@"Distance" atY:185 initialValue:isDis andAction:@selector(toggleDist:)];

    UILabel *sliderLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 220, 40, 20)];
    sliderLabel.text = @"Size:";
    sliderLabel.textColor = [UIColor whiteColor];
    sliderLabel.font = [UIFont systemFontOfSize:12];
    [featureBox addSubview:sliderLabel];
    
    CustomSlider *slider = [[CustomSlider alloc] initWithFrame:CGRectMake(55, 215, 225, 30) min:0.5 max:1.3 value:1.0];
    slider.onChange = ^(float val) {
        previewScale = val;
        previewContentContainer.transform = CGAffineTransformMakeScale(val, val);
    };
    [featureBox addSubview:slider];

    // --- AIM TAB ---
    aimTabContainer = [[UIView alloc] initWithFrame:CGRectMake(15, 50, 440, 250)];
    aimTabContainer.backgroundColor = [UIColor blackColor];
    aimTabContainer.layer.borderColor = [UIColor whiteColor].CGColor;
    aimTabContainer.layer.borderWidth = 1;
    aimTabContainer.layer.cornerRadius = 10;
    aimTabContainer.userInteractionEnabled = YES;
    aimTabContainer.hidden = YES;
    [menuContainer addSubview:aimTabContainer];
    
    UILabel *aimTitle = [[UILabel alloc] initWithFrame:CGRectMake(15, 10, 200, 20)];
    aimTitle.text = @"Aimbot Logic";
    aimTitle.textColor = [UIColor whiteColor];
    aimTitle.font = [UIFont boldSystemFontOfSize:16];
    [aimTabContainer addSubview:aimTitle];
    
    UIView *aimLine = [[UIView alloc] initWithFrame:CGRectMake(15, 35, 410, 1)];
    aimLine.backgroundColor = [UIColor whiteColor];
    [aimTabContainer addSubview:aimLine];
    
    [self addFeatureToView:aimTabContainer withTitle:@"Enable Aimbot" atY:45 initialValue:isAimbot andAction:@selector(toggleAimbot:)];
    
    // FOV Slider
    UILabel *fovLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 85, 200, 20)];
    fovLabel.text = @"FOV Radius:";
    fovLabel.textColor = [UIColor whiteColor];
    fovLabel.font = [UIFont systemFontOfSize:13];
    [aimTabContainer addSubview:fovLabel];
    
    CustomSlider *fovSlider = [[CustomSlider alloc] initWithFrame:CGRectMake(15, 105, 400, 30) min:10 max:400 value:aimFov];
    fovSlider.onChange = ^(float val) { aimFov = val; };
    [aimTabContainer addSubview:fovSlider];
    
    // Distance Slider
    UILabel *distLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 145, 200, 20)];
    distLabel.text = @"Aim Distance (m):";
    distLabel.textColor = [UIColor whiteColor];
    distLabel.font = [UIFont systemFontOfSize:13];
    [aimTabContainer addSubview:distLabel];
    
    CustomSlider *distSlider = [[CustomSlider alloc] initWithFrame:CGRectMake(15, 165, 400, 30) min:10 max:500 value:aimDistance];
    distSlider.onChange = ^(float val) { aimDistance = val; };
    [aimTabContainer addSubview:distSlider];


    // --- SETTING TAB (Empty for now) ---
    settingTabContainer = [[UIView alloc] initWithFrame:CGRectMake(15, 50, 440, 250)];
    settingTabContainer.backgroundColor = [UIColor blackColor];
    settingTabContainer.layer.borderColor = [UIColor whiteColor].CGColor;
    settingTabContainer.layer.borderWidth = 1;
    settingTabContainer.layer.cornerRadius = 10;
    settingTabContainer.userInteractionEnabled = YES;
    settingTabContainer.hidden = YES;
    debugTabContainer.hidden = YES;
    [menuContainer addSubview:settingTabContainer];
    
    UILabel *stTitle = [[UILabel alloc] initWithFrame:CGRectMake(15, 10, 200, 20)];
    stTitle.text = @"Settings";
    stTitle.textColor = [UIColor whiteColor];
    stTitle.font = [UIFont boldSystemFontOfSize:16];
    [settingTabContainer addSubview:stTitle];

    // --- DEBUG TAB ---
    debugTabContainer = [[UIView alloc] initWithFrame:CGRectMake(15, 50, 440, 250)];
    debugTabContainer.backgroundColor = [UIColor blackColor];
    debugTabContainer.layer.borderColor = [UIColor whiteColor].CGColor;
    debugTabContainer.layer.borderWidth = 1;
    debugTabContainer.layer.cornerRadius = 10;
    debugTabContainer.userInteractionEnabled = YES;
    debugTabContainer.hidden = YES;
    [menuContainer addSubview:debugTabContainer];

    UILabel *dbgTitle = [[UILabel alloc] initWithFrame:CGRectMake(15, 8, 200, 20)];
    dbgTitle.text = @"Debug";
    dbgTitle.textColor = [UIColor whiteColor];
    dbgTitle.font = [UIFont boldSystemFontOfSize:16];
    [debugTabContainer addSubview:dbgTitle];

    // Scan toggle
    UIView *scanBtn = [[UIView alloc] initWithFrame:CGRectMake(15, 35, 110, 28)];
    scanBtn.backgroundColor = [UIColor colorWithRed:0.3 green:0.3 blue:0.3 alpha:1.0];
    scanBtn.layer.cornerRadius = 6;
    scanBtn.userInteractionEnabled = YES;
    scanBtnLabel = [[UILabel alloc] initWithFrame:scanBtn.bounds];
    scanBtnLabel.text = @"Scan: OFF";
    scanBtnLabel.textColor = [UIColor whiteColor];
    scanBtnLabel.textAlignment = NSTextAlignmentCenter;
    scanBtnLabel.font = [UIFont boldSystemFontOfSize:11];
    scanBtnLabel.userInteractionEnabled = NO;
    [scanBtn addSubview:scanBtnLabel];
    UITapGestureRecognizer *scanTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleDebugScan)];
    [scanBtn addGestureRecognizer:scanTap];
    [debugTabContainer addSubview:scanBtn];

    // Clear button
    UIView *clrBtn = [[UIView alloc] initWithFrame:CGRectMake(125, 35, 80, 28)];
    clrBtn.backgroundColor = [UIColor colorWithRed:0.5 green:0.2 blue:0.2 alpha:1.0];
    clrBtn.layer.cornerRadius = 6;
    clrBtn.userInteractionEnabled = YES;
    UILabel *clrLbl = [[UILabel alloc] initWithFrame:clrBtn.bounds];
    clrLbl.text = @"Clear";
    clrLbl.textColor = [UIColor whiteColor];
    clrLbl.textAlignment = NSTextAlignmentCenter;
    clrLbl.font = [UIFont boldSystemFontOfSize:12];
    clrLbl.userInteractionEnabled = NO;
    [clrBtn addSubview:clrLbl];
    UITapGestureRecognizer *clrTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(clearDebugLog)];
    [clrBtn addGestureRecognizer:clrTap];
    [debugTabContainer addSubview:clrBtn];

    // Log view (selectable/copyable)
    debugLogView = [[UITextView alloc] initWithFrame:CGRectMake(10, 70, 420, 170)];
    debugLogView.backgroundColor = [UIColor colorWithWhite:0.1 alpha:1.0];
    debugLogView.textColor = [UIColor greenColor];
    debugLogView.font = [UIFont fontWithName:@"Menlo" size:10];
    debugLogView.editable = NO;
    debugLogView.selectable = YES;
    debugLogView.text = @"Log (tap Scan to run)\n";
    [debugTabContainer addSubview:debugLogView];
}

- (void)appendDebugLog:(NSString *)line {
    if (!debugLogView) return;
    NSString *cur = debugLogView.text ?: @"";
    debugLogView.text = [cur stringByAppendingFormat:@"%@\n", line];
    [debugLogView scrollRangeToVisible:NSMakeRange(debugLogView.text.length, 0)];
}

- (void)clearDebugLog {
    debugLogView.text = @"";
}

- (void)toggleDebugScan {
    debugScanEnabled = !debugScanEnabled;
    if (debugScanEnabled) {
        scanBtnLabel.text = @"Scan: ON";
        scanBtnLabel.superview.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:0.2 alpha:1.0];
        [self appendDebugLog:@"--- Continuous scan ON ---"];
        debugScanTimer = [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(continuousScan) userInfo:nil repeats:YES];
    } else {
        scanBtnLabel.text = @"Scan: OFF";
        scanBtnLabel.superview.backgroundColor = [UIColor colorWithRed:0.3 green:0.3 blue:0.3 alpha:1.0];
        [debugScanTimer invalidate];
        debugScanTimer = nil;
        [self appendDebugLog:@"--- Scan OFF ---"];
    }
}

- (void)continuousScan {
    if (!debugScanEnabled) return;
    if (Moudule_Base == (uint64_t)-1 || Moudule_Base == 0) {
        [self appendDebugLog:@"Base not ready"];
        return;
    }
    // Try TypeInfo
    uint64_t ti = ReadAddr<uint64_t>(Moudule_Base + 0xBFD8978);
    if (isVaildPtr(ti)) {
        uint64_t sf = ReadAddr<uint64_t>(ti + 0xB8);
        if (isVaildPtr(sf)) {
            uint64_t mg = ReadAddr<uint64_t>(sf + 0x8);
            if (looksMatchGame(mg)) {
                [self appendDebugLog:[NSString stringWithFormat:@"TypeInfo OK: 0x%llx", mg]];
                return;
            }
        }
    }
    // Quick scan (sample every 0x1000 to avoid lag)
    static uint64_t lastOff = 0x800000;
    const uint64_t end = 0x3000000;
    int found = 0;
    for (int i = 0; i < 200 && lastOff < end; i++, lastOff += 0x1000) {
        uint64_t cand = ReadAddr<uint64_t>(Moudule_Base + lastOff);
        if (isVaildPtr(cand) && looksMatchGame(cand)) {
            [self appendDebugLog:[NSString stringWithFormat:@"FOUND base+0x%llx -> 0x%llx", lastOff, cand]];
            found++;
        }
    }
    if (lastOff >= end) lastOff = 0x800000;
    if (found == 0) {
        [self appendDebugLog:[NSString stringWithFormat:@"scan @0x%llx ...", lastOff]];
    }
}

- (void)tabTapped:(UITapGestureRecognizer *)gesture {
    UIView *sender = gesture.view;
    mainTabContainer.hidden = YES;
    aimTabContainer.hidden = YES;
    settingTabContainer.userInteractionEnabled = YES;
    settingTabContainer.hidden = YES;
    debugTabContainer.hidden = YES;
    
    // Reset all tab colors
    for (UIView *sub in sender.superview.subviews) {
        if (sub.tag >= 0 && sub.tag <= 3) {
            sub.backgroundColor = [UIColor colorWithRed:0.3 green:0.3 blue:0.3 alpha:1.0];
        }
    }
    // Highlight active
    sender.backgroundColor = [UIColor colorWithRed:0.2 green:0.2 blue:0.2 alpha:1.0];
    
    if (sender.tag == 0) mainTabContainer.hidden = NO;
    if (sender.tag == 1) aimTabContainer.hidden = NO;
    if (sender.tag == 2) settingTabContainer.hidden = NO;
    if (sender.tag == 3) debugTabContainer.hidden = NO;
}

- (void)drawPreviewElements {
    CGFloat w = previewView.frame.size.width;  
    CGFloat h = previewView.frame.size.height; 
    CGFloat cx = w / 2;
    CGFloat startY = 45; 
    
    previewNameLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 20, w, 15)];
    previewNameLabel.text = @"ID PlayerName";
    previewNameLabel.textColor = [UIColor greenColor];
    previewNameLabel.textAlignment = NSTextAlignmentCenter;
    previewNameLabel.font = [UIFont boldSystemFontOfSize:11];
    [previewContentContainer addSubview:previewNameLabel];
    
    CGFloat barW = 70;
    healthBarContainer = [[UIView alloc] initWithFrame:CGRectMake(cx - barW/2, 38, barW, 2)];
    healthBarContainer.backgroundColor = [UIColor greenColor];
    [previewContentContainer addSubview:healthBarContainer];
    
    CGFloat boxW = 70;
    CGFloat boxH = 130;
    CGFloat bx = cx - boxW/2;
    CGFloat by = startY;
    
    boxContainer = [[UIView alloc] initWithFrame:previewView.bounds];
    [previewContentContainer addSubview:boxContainer];
    
    CGFloat lineLen = 15;
    UIColor *boxColor = [UIColor whiteColor];
    [self addLineRect:CGRectMake(bx, by, lineLen, 1) color:boxColor parent:boxContainer];
    [self addLineRect:CGRectMake(bx, by, 1, lineLen) color:boxColor parent:boxContainer];
    [self addLineRect:CGRectMake(bx + boxW - lineLen, by, lineLen, 1) color:boxColor parent:boxContainer];
    [self addLineRect:CGRectMake(bx + boxW, by, 1, lineLen) color:boxColor parent:boxContainer];
    [self addLineRect:CGRectMake(bx, by + boxH, lineLen, 1) color:boxColor parent:boxContainer];
    [self addLineRect:CGRectMake(bx, by + boxH - lineLen, 1, lineLen) color:boxColor parent:boxContainer];
    [self addLineRect:CGRectMake(bx + boxW - lineLen, by + boxH, lineLen, 1) color:boxColor parent:boxContainer];
    [self addLineRect:CGRectMake(bx + boxW, by + boxH - lineLen, 1, lineLen) color:boxColor parent:boxContainer];

    skeletonContainer = [[UIView alloc] initWithFrame:previewView.bounds];
    [previewContentContainer addSubview:skeletonContainer];
    
    UIColor *skelColor = [UIColor whiteColor];
    CGFloat skelThick = 1.0;
    
    CGFloat headRad = 7;
    CGFloat headY = by + 15;
    UIView *head = [[UIView alloc] initWithFrame:CGRectMake(cx - headRad, headY - headRad, headRad*2, headRad*2)];
    head.layer.borderColor = skelColor.CGColor;
    head.layer.borderWidth = skelThick;
    head.layer.cornerRadius = headRad;
    [skeletonContainer addSubview:head];
    
    CGPoint pNeck = CGPointMake(cx, headY + headRad);
    CGPoint pPelvis = CGPointMake(cx, by + 65);
    CGPoint pShoulderL = CGPointMake(cx - 15, by + 30);
    CGPoint pShoulderR = CGPointMake(cx + 15, by + 30);
    CGPoint pElbowL = CGPointMake(cx - 20, by + 50);
    CGPoint pElbowR = CGPointMake(cx + 20, by + 50);
    CGPoint pHandL = CGPointMake(cx - 20, by + 70);
    CGPoint pHandR = CGPointMake(cx + 20, by + 70);
    CGPoint pKneeL = CGPointMake(cx - 12, by + 95);
    CGPoint pKneeR = CGPointMake(cx + 12, by + 95);
    CGPoint pFootL = CGPointMake(cx - 15, by + 125);
    CGPoint pFootR = CGPointMake(cx + 15, by + 125);
    
    [self addLineFrom:pNeck to:pPelvis color:skelColor width:skelThick inView:skeletonContainer];
    [self addLineFrom:pShoulderL to:pShoulderR color:skelColor width:skelThick inView:skeletonContainer];
    [self addLineFrom:CGPointMake(cx, by+30) to:pShoulderL color:skelColor width:skelThick inView:skeletonContainer];
    [self addLineFrom:pShoulderL to:pElbowL color:skelColor width:skelThick inView:skeletonContainer];
    [self addLineFrom:pElbowL to:pHandL color:skelColor width:skelThick inView:skeletonContainer];
    [self addLineFrom:CGPointMake(cx, by+30) to:pShoulderR color:skelColor width:skelThick inView:skeletonContainer];
    [self addLineFrom:pShoulderR to:pElbowR color:skelColor width:skelThick inView:skeletonContainer];
    [self addLineFrom:pElbowR to:pHandR color:skelColor width:skelThick inView:skeletonContainer];
    [self addLineFrom:pPelvis to:pKneeL color:skelColor width:skelThick inView:skeletonContainer];
    [self addLineFrom:pKneeL to:pFootL color:skelColor width:skelThick inView:skeletonContainer];
    [self addLineFrom:pPelvis to:pKneeR color:skelColor width:skelThick inView:skeletonContainer];
    [self addLineFrom:pKneeR to:pFootR color:skelColor width:skelThick inView:skeletonContainer];
    
    previewDistLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, by + boxH + 5, w, 15)];
    previewDistLabel.text = @"Distance";
    previewDistLabel.textColor = [UIColor whiteColor];
    previewDistLabel.textAlignment = NSTextAlignmentCenter;
    previewDistLabel.font = [UIFont systemFontOfSize:10];
    [previewContentContainer addSubview:previewDistLabel];
}

- (void)updatePreviewVisibility {
    boxContainer.hidden = !isBox;
    skeletonContainer.hidden = !isBone;
    healthBarContainer.hidden = !isHealth;
    previewNameLabel.hidden = !isName;
    previewDistLabel.hidden = !isDis;
    
    if (isBox && isBone) {
        [previewContentContainer bringSubviewToFront:boxContainer];
    }
}

// --- Toggle Handlers ---
- (void)toggleBox:(CustomSwitch *)sender { isBox = sender.isOn; boxContainer.hidden = !isBox; }
- (void)toggleBone:(CustomSwitch *)sender { isBone = sender.isOn; skeletonContainer.hidden = !isBone; }
- (void)toggleHealth:(CustomSwitch *)sender { isHealth = sender.isOn; healthBarContainer.hidden = !isHealth; }
- (void)toggleName:(CustomSwitch *)sender { isName = sender.isOn; previewNameLabel.hidden = !isName; }
- (void)toggleDist:(CustomSwitch *)sender { isDis = sender.isOn; previewDistLabel.hidden = !isDis; }
- (void)toggleAimbot:(CustomSwitch *)sender { isAimbot = sender.isOn; }

- (void)fovChanged:(UISlider *)sender { aimFov = sender.value; }
- (void)distChanged:(UISlider *)sender { aimDistance = sender.value; }

- (void)addLineRect:(CGRect)frame color:(UIColor *)color parent:(UIView *)parent {
    UIView *v = [[UIView alloc] initWithFrame:frame];
    v.backgroundColor = color;
    [parent addSubview:v];
}
- (void)addLineFrom:(CGPoint)p1 to:(CGPoint)p2 color:(UIColor *)color width:(CGFloat)width inView:(UIView *)view {
    UIView *line = [[UIView alloc] init];
    line.backgroundColor = color;
    CGFloat dx = p2.x - p1.x;
    CGFloat dy = p2.y - p1.y;
    CGFloat len = sqrt(dx*dx + dy*dy);
    CGFloat angle = atan2(dy, dx);
    line.frame = CGRectMake(p1.x, p1.y, len, width);
    line.layer.anchorPoint = CGPointMake(0, 0.5);
    line.center = p1;
    line.transform = CGAffineTransformMakeRotation(angle);
    [view addSubview:line];
}

- (void)sliderValueChanged:(UISlider *)sender {
    previewScale = sender.value;
    [UIView animateWithDuration:0.1 animations:^{
        self->previewContentContainer.transform = CGAffineTransformMakeScale(self->previewScale, self->previewScale);
    }];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (self.superview) self.frame = self.superview.bounds;
    CGRect screenBounds = self.bounds;
    CGPoint btnCenter = floatingButton.center;
    CGFloat halfW = floatingButton.bounds.size.width / 2;
    CGFloat halfH = floatingButton.bounds.size.height / 2;
    if (btnCenter.x < halfW) btnCenter.x = halfW;
    if (btnCenter.x > screenBounds.size.width - halfW) btnCenter.x = screenBounds.size.width - halfW;
    if (btnCenter.y < halfH) btnCenter.y = halfH;
    if (btnCenter.y > screenBounds.size.height - halfH) btnCenter.y = screenBounds.size.height - halfH;
    floatingButton.center = btnCenter;
}

- (void)showMenu {
    menuContainer.hidden = NO;
    floatingButton.hidden = YES;
    menuContainer.transform = CGAffineTransformMakeScale(0.1, 0.1);
    [self centerMenu];
    [UIView animateWithDuration:0.3 animations:^{
        self->menuContainer.transform = CGAffineTransformIdentity;
    }];
    [self updatePreviewVisibility];
}

- (void)hideMenu {
    [UIView animateWithDuration:0.3 animations:^{
        self->menuContainer.transform = CGAffineTransformMakeScale(0.1, 0.1);
    } completion:^(BOOL finished) {
        self->menuContainer.hidden = YES;
        self->floatingButton.hidden = NO;
        self->menuContainer.transform = CGAffineTransformIdentity;
    }];
}

- (void)centerMenu {
    menuContainer.center = CGPointMake(self.bounds.size.width / 2, self.bounds.size.height / 2);
}
- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    CGPoint touchPoint = [gesture locationInView:self];
    if (gesture.state == UIGestureRecognizerStateBegan) {
        _initialTouchPoint = touchPoint;
    } else if (gesture.state == UIGestureRecognizerStateChanged) {
        CGFloat deltaX = touchPoint.x - _initialTouchPoint.x;
        CGFloat deltaY = touchPoint.y - _initialTouchPoint.y;
        UIView *viewToMove = (gesture.view == floatingButton) ? floatingButton : menuContainer;
        viewToMove.center = CGPointMake(viewToMove.center.x + deltaX, viewToMove.center.y + deltaY);
        _initialTouchPoint = touchPoint;
    }
}

- (void)SetUpBase {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Moudule_Base = (uint64_t)GetGameModule_Base((char*)"freefireth");
    });
}

- (void)updateFrame {
    if (!self.window) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (CALayer *layer in self.drawingLayers) {
        [layer removeFromSuperlayer];
    }
    [self.drawingLayers removeAllObjects];
    
    // Draw FOV Circle
    if (isAimbot) {
        float screenX = self.bounds.size.width / 2;
        float screenY = self.bounds.size.height / 2;
        
        CAShapeLayer *circleLayer = [CAShapeLayer layer];
        UIBezierPath *path = [UIBezierPath bezierPathWithArcCenter:CGPointMake(screenX, screenY) radius:aimFov startAngle:0 endAngle:2 * M_PI clockwise:YES];
        circleLayer.path = path.CGPath;
        circleLayer.fillColor = [UIColor clearColor].CGColor;
        circleLayer.strokeColor = [UIColor colorWithRed:1.0 green:1.0 blue:1.0 alpha:0.5].CGColor;
        circleLayer.lineWidth = 1.0;
        [self.drawingLayers addObject:circleLayer];
    }
    
    [self renderESPToLayers:self.drawingLayers];
    
    for (CALayer *layer in self.drawingLayers) {
        [self.layer addSublayer:layer];
    }
    [CATransaction commit];
    [self setNeedsDisplay];
}

- (void)dealloc {
    [self.displayLink invalidate];
    self.displayLink = nil;
}

static inline void DrawBoneLine(
    NSMutableArray<CALayer *> *layers,
    CGPoint p1,
    CGPoint p2,
    UIColor *color,
    CGFloat width
) {
    CGFloat dx = p2.x - p1.x;
    CGFloat dy = p2.y - p1.y;
    CGFloat len = sqrt(dx*dx + dy*dy);
    if (len < 2.0f) return;

    CALayer *line = [CALayer layer];
    line.backgroundColor = color.CGColor;
    line.bounds = CGRectMake(0, 0, len, width);
    line.position = p1;
    line.anchorPoint = CGPointMake(0, 0.5);
    line.transform = CATransform3DMakeRotation(atan2(dy, dx), 0, 0, 1);
    [layers addObject:line];
}


Quaternion GetRotationToLocation(Vector3 targetLocation, float y_bias, Vector3 myLoc){
    return Quaternion::LookRotation((targetLocation + Vector3(0, y_bias, 0)) - myLoc, Vector3(0, 1, 0));
}

void set_aim(uint64_t player, Quaternion rotation) {
    if (!isVaildPtr(player)) return;
    
    WriteAddr<Quaternion>(player + 0x550, rotation);
}

bool get_IsFiring(uint64_t player) {
    if (!isVaildPtr(player)) return false;
    bool fireState = ReadAddr<bool>(player + 0x758);
    return fireState;
}


bool get_IsVisible(uint64_t player) {
    if (!isVaildPtr(player)) return false;
    
    uint64_t visibleObj = ReadAddr<uint64_t>(player + 0x930);
    if (!isVaildPtr(visibleObj)) return false;

    int visibleFlags = ReadAddr<int>(visibleObj + 0x10); 
    return (visibleFlags & 0x1) == 0;
}


- (void)renderESPToLayers:(NSMutableArray<CALayer *> *)layers {
    if (Moudule_Base == -1) return;

    uint64_t matchGame = getMatchGame(Moudule_Base);
    uint64_t camera = CameraMain(matchGame);
    if (!isVaildPtr(camera)) return;

    uint64_t match = getMatch(matchGame);
    if (!isVaildPtr(match)) return;

    uint64_t myPawnObject = getLocalPlayer(match);
    if (!isVaildPtr(myPawnObject)) return;
    
    uint64_t mainCameraTransform = ReadAddr<uint64_t>(myPawnObject + 0x3E8);
    Vector3 myLocation = getPositionExt(mainCameraTransform);
    
    uint64_t player = ReadAddr<uint64_t>(match + 0xC8);
    uint64_t tValue = ReadAddr<uint64_t>(player + 0x28);
    int coutValue = ReadAddr<int>(tValue + 0x18);
    
    float *matrix = GetViewMatrix(camera);
    float viewWidth = self.bounds.size.width;
    float viewHeight = self.bounds.size.height;
    CGPoint screenCenter = CGPointMake(viewWidth / 2, viewHeight / 2);

    // Variables for Aimbot
    uint64_t bestTarget = 0;
    int minHP = 99999;
    bool isVis = false;
    bool isFire = false;
    
    for (int i = 0; i < coutValue; i++) {
        uint64_t PawnObject = ReadAddr<uint64_t>(tValue + 0x20 + 8 * i);
        if (!isVaildPtr(PawnObject)) continue;

        bool isLocalTeam = isLocalTeamMate(myPawnObject, PawnObject);
        if (isLocalTeam) continue;
        
        int CurHP = get_CurHP(PawnObject);
        if (CurHP <= 0) continue; 

        Vector3 HeadPos     = getPositionExt(getHead(PawnObject));
        isFire              = get_IsFiring(myPawnObject);
        
        float dis = Vector3::Distance(myLocation, HeadPos);
        if (dis > 400.0f) continue;

        
        if (isAimbot && dis <= aimDistance) {
            Vector3 w2sAim = WorldToScreen(HeadPos, matrix, viewWidth, viewHeight);

            float deltaX = w2sAim.x - screenCenter.x;
            float deltaY = w2sAim.y - screenCenter.y;
            float distanceFromCenter = sqrt(deltaX * deltaX + deltaY * deltaY);
            
            if (distanceFromCenter <= aimFov) {
                if (CurHP < minHP) {
                    minHP = CurHP;
                    
                    isVis = get_IsVisible(PawnObject);
                    bestTarget = PawnObject;
                }
            }
            
        }

        if (dis > 220.0f) continue; 

        Vector3 RightToePos = getPositionExt(getRightToeNode(PawnObject));
        Vector3 HipPos      = getPositionExt(getHip(PawnObject));
        Vector3 L_Ankle     = getPositionExt(getLeftAnkle(PawnObject));
        Vector3 R_Ankle     = getPositionExt(getRightAnkle(PawnObject));
        
        Vector3 L_Shoulder  = getPositionExt(getLeftShoulder(PawnObject));
        Vector3 R_Shoulder  = getPositionExt(getRightShoulder(PawnObject));
        Vector3 L_Elbow     = getPositionExt(getLeftElbow(PawnObject));
        Vector3 R_Elbow     = getPositionExt(getRightElbow(PawnObject));
        Vector3 L_Hand      = getPositionExt(getLeftHand(PawnObject));
        Vector3 R_Hand      = getPositionExt(getRightHand(PawnObject));

        Vector3 HeadTop     = HeadPos; HeadTop.y += 0.2f;
        Vector3 w2sHead     = WorldToScreen(HeadTop, matrix, viewWidth, viewHeight);
        Vector3 w2sToe      = WorldToScreen(RightToePos, matrix, viewWidth, viewHeight);

        Vector3 wHead       = WorldToScreen(HeadPos, matrix, viewWidth, viewHeight);
        Vector3 wHip        = WorldToScreen(HipPos, matrix, viewWidth, viewHeight);

        if (isBone) {
             Vector3 wLS = WorldToScreen(L_Shoulder, matrix, viewWidth, viewHeight);
             Vector3 wRS = WorldToScreen(R_Shoulder, matrix, viewWidth, viewHeight);
             Vector3 wLE = WorldToScreen(L_Elbow, matrix, viewWidth, viewHeight);
             Vector3 wRE = WorldToScreen(R_Elbow, matrix, viewWidth, viewHeight);
             Vector3 wLH = WorldToScreen(L_Hand, matrix, viewWidth, viewHeight);
             Vector3 wRH = WorldToScreen(R_Hand, matrix, viewWidth, viewHeight);
             Vector3 wLA = WorldToScreen(L_Ankle, matrix, viewWidth, viewHeight);
             Vector3 wRA = WorldToScreen(R_Ankle, matrix, viewWidth, viewHeight);

            UIColor *boneColor = [UIColor whiteColor];
            CGFloat boneWidth = 1.0f;

            DrawBoneLine(layers, CGPointMake(wHead.x, wHead.y), CGPointMake(wHip.x, wHip.y), boneColor, boneWidth);
            DrawBoneLine(layers, CGPointMake(wLS.x, wLS.y), CGPointMake(wRS.x, wRS.y), boneColor, boneWidth);
            DrawBoneLine(layers, CGPointMake(wLS.x, wLS.y), CGPointMake(wLE.x, wLE.y), boneColor, boneWidth);
            DrawBoneLine(layers, CGPointMake(wLE.x, wLE.y), CGPointMake(wLH.x, wLH.y), boneColor, boneWidth);
            DrawBoneLine(layers, CGPointMake(wRS.x, wRS.y), CGPointMake(wRE.x, wRE.y), boneColor, boneWidth);
            DrawBoneLine(layers, CGPointMake(wRE.x, wRE.y), CGPointMake(wRH.x, wRH.y), boneColor, boneWidth);
            DrawBoneLine(layers, CGPointMake(wHip.x, wHip.y), CGPointMake(wLA.x, wLA.y), boneColor, boneWidth);
            DrawBoneLine(layers, CGPointMake(wHip.x, wHip.y), CGPointMake(wRA.x, wRA.y), boneColor, boneWidth);
        }

        float boxHeight = abs(w2sHead.y - w2sToe.y);
        float boxWidth = boxHeight * 0.5f;
        float x = w2sHead.x - boxWidth * 0.5f;
        float y = w2sHead.y;
        
        if (isBox) {
            CALayer *boxLayer = [CALayer layer];
            boxLayer.frame = CGRectMake(x, y, boxWidth, boxHeight);
            boxLayer.borderColor = [UIColor redColor].CGColor;
            boxLayer.borderWidth = 1.0;
            boxLayer.cornerRadius = 3.0;
            [layers addObject:boxLayer];
        }
        
        if (isName) {
            NSString *Name = GetNickName(PawnObject);
            if (Name.length > 0) {
                CATextLayer *nameLayer = [CATextLayer layer];
                nameLayer.string = Name;
                nameLayer.fontSize = 10;
                nameLayer.frame = CGRectMake(x - 20, y - 15, boxWidth + 40, 15);
                nameLayer.alignmentMode = kCAAlignmentCenter;
                nameLayer.foregroundColor = [UIColor greenColor].CGColor;
                [layers addObject:nameLayer];
            }
        }
        
        if (isHealth) {
            int MaxHP = get_MaxHP(PawnObject);
            if (MaxHP > 0) {
                float hpRatio = (float)CurHP / (float)MaxHP;
                if (hpRatio < 0) hpRatio = 0; if (hpRatio > 1) hpRatio = 1;
                
                float barWidth = 4.0;
                float barHeight = boxHeight;
                float filledHeight = barHeight * hpRatio;
                
                CALayer *bgBar = [CALayer layer];
                bgBar.frame = CGRectMake(x - barWidth - 2, y, barWidth, barHeight);
                bgBar.backgroundColor = [UIColor redColor].CGColor;
                [layers addObject:bgBar];
                
                CALayer *hpBar = [CALayer layer];
                hpBar.frame = CGRectMake(x - barWidth - 2, y + (barHeight - filledHeight), barWidth, filledHeight);
                hpBar.backgroundColor = [UIColor greenColor].CGColor;
                [layers addObject:hpBar];
            }
        }
        
        if (isDis) {
            CATextLayer *distLayer = [CATextLayer layer];
            distLayer.string = [NSString stringWithFormat:@"[%.0fm]", dis];
            distLayer.fontSize = 9;
            distLayer.frame = CGRectMake(x - 10, y + boxHeight + 2, boxWidth + 20, 12);
            distLayer.alignmentMode = kCAAlignmentCenter;
            distLayer.foregroundColor = [UIColor whiteColor].CGColor;
            [layers addObject:distLayer];
        }
    }

    if (isAimbot && isVaildPtr(bestTarget) && isFire) {
        Vector3 EnemyHead = getPositionExt(getHead(bestTarget));

        Quaternion targetLook = GetRotationToLocation(EnemyHead, 0.1f, myLocation);

        set_aim(myPawnObject, targetLook);
        
        
    }
}

@end