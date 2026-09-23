//
//  MainWindowController.h
//  DiskArbitrator
//
//  Programmatic rebuild of the main window to match the OpenDesign prototype
//  (sidebar + telemetry + multi-column device table + disk inspector + mode switch).
//

#import <Cocoa/Cocoa.h>
#import "Disk.h"

@class AppController;
@class Arbitrator;

@interface Disk (DiskArbitratorUI)
@property (nonatomic, readonly) BOOL isDiskImage;
@property (nonatomic, readonly) NSString *uiVolumeKind;
@property (nonatomic, readonly) NSString *uiProtocol;
@property (nonatomic, readonly) NSString *uiCapacity;
@property (nonatomic, readonly) NSString *uiMountState;
@property (nonatomic, readonly) NSString *uiMediaName;
@property (nonatomic, readonly) NSString *uiMediaKind;
@property (nonatomic, readonly) NSString *uiBlockSize;
@property (nonatomic, readonly) NSString *uiVendor;
@property (nonatomic, readonly) NSString *uiModel;
@property (nonatomic, readonly) NSString *uiMountPath;
@end

@interface MainWindowController : NSWindowController <NSTableViewDelegate>

@property (nonatomic, strong) AppController *appController;
@property (nonatomic, strong) Arbitrator *arbitrator;

@property (nonatomic, strong) NSArrayController *disksArrayController;
@property (nonatomic, strong) NSTableView *tableView;

@property (nonatomic, strong) NSSegmentedControl *modeSegmentControl;
@property (nonatomic, strong) NSTextField *modeHeadlineLabel;
@property (nonatomic, strong) NSTextField *modeDescriptionLabel;

@property (nonatomic, strong) NSTextField *telemetryStatusValue;
@property (nonatomic, strong) NSTextField *telemetryShieldValue;
@property (nonatomic, strong) NSTextField *telemetryDevicesValue;
@property (nonatomic, strong) NSTextField *badgeAllCount;
@property (nonatomic, strong) NSTextField *badgeExternalCount;
@property (nonatomic, strong) NSTextField *badgeImagesCount;
@property (nonatomic, strong) NSTextField *badgeRejectionsCount;
@property (nonatomic, strong) NSTextField *launchAgentStatusLabel;

// Disk inspector detail labels
@property (nonatomic, strong) NSTextField *inspectorTitleLabel;
@property (nonatomic, strong) NSTextField *inspectorBSDName;
@property (nonatomic, strong) NSTextField *inspectorMountPath;
@property (nonatomic, strong) NSTextField *inspectorMediaKind;
@property (nonatomic, strong) NSTextField *inspectorMediaProtocol;
@property (nonatomic, strong) NSTextField *inspectorBlockSize;
@property (nonatomic, strong) NSTextField *inspectorVendor;
@property (nonatomic, strong) NSTextField *inspectorModel;
@property (nonatomic, strong) NSTextField *inspectorRemovable;
@property (nonatomic, strong) NSTextField *inspectorEjectable;

- (instancetype)initWithAppController:(AppController *)appController arbitrator:(Arbitrator *)arbitrator;
- (Disk *)selectedDisk;
- (void)refreshDisplays;

@end
