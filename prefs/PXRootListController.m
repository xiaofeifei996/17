#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSViewController.h>
#import <math.h>

#pragma mark - PXPageHostController

@interface PXPageHostController : PSViewController

@property(nonatomic, strong) UIViewController *contentController;

@end

@implementation PXPageHostController

- (instancetype)initForContentSize:(CGSize)contentSize
{
    return [super initWithNibName:nil bundle:nil];
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    [self installContentIfReady];
}

- (void)setSpecifier:(PSSpecifier *)specifier
{
    [super setSpecifier:specifier];

    if (self.isViewLoaded) {
        [self installContentIfReady];
    }
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    [self installContentIfReady];
}

- (void)installContentIfReady
{
    if (self.contentController != nil) {
        return;
    }

    PSSpecifier *specifier = self.specifier;

    if (specifier == nil) {
        return;
    }

    NSString *identifier =
        [specifier propertyForKey:@"id"];

    NSDictionary *pages = @{
        @"picker"       : @"PXAppPickerController",
        @"launcher"     : @"PXLauncherController",
        @"radius"       : @"PXCornerRadiusController",
        @"dock"         : @"PXDockController",
        @"gestures"     : @"PXGestureAreaController",
        @"urlBlacklist" : @"PXExternalBlacklistController",
        @"backup"       : @"PXBackupController"
    };

    NSString *className =
        pages[identifier ?: @""];

    if (className.length == 0) {
        return;
    }

    Class pageClass =
        NSClassFromString(className);

    if (pageClass == Nil) {
        return;
    }

    if (![pageClass isSubclassOfClass:[UIViewController class]]) {
        return;
    }

    UIViewController *page =
        [[pageClass alloc] init];

    if (page == nil) {
        return;
    }

    self.contentController = page;

    [self addChildViewController:page];

    UIView *contentView = page.view;

    if (contentView == nil) {
        return;
    }

    contentView.frame = self.view.bounds;

    contentView.autoresizingMask =
        UIViewAutoresizingFlexibleWidth |
        UIViewAutoresizingFlexibleHeight;

    [self.view addSubview:contentView];

    [page didMoveToParentViewController:self];

    NSString *pageTitle = page.title;

    if (pageTitle.length > 0) {
        self.title = pageTitle;
    } else {
        self.title = specifier.name;
    }

    self.navigationItem.rightBarButtonItem =
        page.navigationItem.rightBarButtonItem;

    if (@available(iOS 11.0, *)) {
        self.navigationItem.searchController =
            page.navigationItem.searchController;

        self.navigationItem.hidesSearchBarWhenScrolling =
            page.navigationItem.hidesSearchBarWhenScrolling;
    }
}

- (BOOL)canBeShownFromSuspendedState
{
    return YES;
}

@end


#pragma mark - PXSettingsListController

@interface PXSettingsListController : PSListController

@end

@implementation PXSettingsListController

- (NSMutableArray *)specifiers
{
    if (_specifiers == nil) {

        NSString *page =
            [self.specifier propertyForKey:@"id"];

        NSDictionary *pages = @{
            @"window"   : @"Window",
            @"keyboard" : @"Keyboard",
            @"external" : @"External",
            @"system"   : @"System"
        };

        NSString *plistName =
            pages[page ?: @""];

        if (plistName.length == 0) {
            plistName = @"Root";
        }

        _specifiers =
            [self loadSpecifiersFromPlistName:plistName
                                       target:self];
    }

    return _specifiers;
}


#pragma mark - Custom Slider Cells

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    PSSpecifier *specifier =
        [self specifierAtIndexPath:indexPath];

    NSString *key =
        [specifier propertyForKey:@"key"];

    BOOL horizontal =
        [key isEqualToString:@"externalKeyboardHorizontalPercent"];

    BOOL focus =
        [key isEqualToString:@"internalKeyboardZoomPercent"];

    BOOL dim =
        [key isEqualToString:@"keyboardDimOpacity"];

    if (horizontal || focus || dim) {

        NSString *title;

        if (focus) {
            title = @"内置键盘放大倍数";
        } else if (horizontal) {
            title = @"横屏外置键盘位置";
        } else {
            title = @"键盘关闭遮罩深度";
        }

        int minimum =
            focus ? 100 : 0;

        int maximum;

        if (focus) {
            maximum = 200;
        } else if (horizontal) {
            maximum = 100;
        } else {
            maximum = 60;
        }

        CGFloat multiplier =
            (horizontal || focus) ? 1.0 : 100.0;

        UITableViewCell *cell =
            [[UITableViewCell alloc]
                initWithStyle:UITableViewCellStyleDefault
                reuseIdentifier:nil];

        cell.selectionStyle =
            UITableViewCellSelectionStyleNone;

        if (@available(iOS 13.0, *)) {
            cell.backgroundColor =
                UIColor.secondarySystemGroupedBackgroundColor;
        }

        UILabel *label =
            [[UILabel alloc] init];

        label.font =
            [UIFont preferredFontForTextStyle:UIFontTextStyleBody];

        label.translatesAutoresizingMaskIntoConstraints =
            NO;

        UISlider *slider =
            [[UISlider alloc] init];

        slider.translatesAutoresizingMaskIntoConstraints =
            NO;

        slider.minimumValue =
            minimum;

        slider.maximumValue =
            maximum;

        id preferenceValue =
            [self readPreferenceValue:specifier];

        CGFloat currentValue =
            [preferenceValue respondsToSelector:@selector(floatValue)]
                ? [preferenceValue floatValue] * multiplier
                : minimum;

        if (currentValue < minimum) {
            currentValue = minimum;
        }

        if (currentValue > maximum) {
            currentValue = maximum;
        }

        slider.value = currentValue;

        label.text =
            [NSString stringWithFormat:@"%@：%.0f%%",
                                       title,
                                       slider.value];

        UIButton *button =
            [UIButton buttonWithType:UIButtonTypeSystem];

        button.translatesAutoresizingMaskIntoConstraints =
            NO;

        if (@available(iOS 13.0, *)) {
            UIImage *image =
                [UIImage systemImageNamed:@"keyboard"];

            if (image != nil) {
                [button setImage:image
                        forState:UIControlStateNormal];
            }
        }

        button.accessibilityLabel =
            [@"输入" stringByAppendingString:title];

        __weak typeof(self) weakSelf = self;

        [slider addAction:
            [UIAction actionWithHandler:
                ^(__kindof UIAction *action) {

            UISlider *control =
                (UISlider *)action.sender;

            control.value =
                roundf(control.value);

            label.text =
                [NSString stringWithFormat:@"%@：%.0f%%",
                                           title,
                                           control.value];

            typeof(self) strongSelf =
                weakSelf;

            if (strongSelf != nil) {

                [strongSelf
                    setPreferenceValue:
                        @(control.value / multiplier)
                    specifier:specifier];
            }

        }]
        forControlEvents:UIControlEventValueChanged];


        __weak UISlider *weakSlider =
            slider;

        [button addAction:
            [UIAction actionWithHandler:
                ^(__kindof UIAction *action) {

            UISlider *currentSlider =
                weakSlider;

            if (currentSlider == nil) {
                return;
            }

            UIAlertController *alert =
                [UIAlertController
                    alertControllerWithTitle:title
                    message:
                        [NSString stringWithFormat:
                            @"输入 %d–%d（%%）",
                            minimum,
                            maximum]
                    preferredStyle:
                        UIAlertControllerStyleAlert];

            [alert addTextFieldWithConfigurationHandler:
                ^(UITextField *field) {

                field.keyboardType =
                    UIKeyboardTypeNumberPad;

                field.text =
                    [NSString stringWithFormat:
                        @"%.0f",
                        currentSlider.value];
            }];

            [alert addAction:
                [UIAlertAction
                    actionWithTitle:@"取消"
                    style:UIAlertActionStyleCancel
                    handler:nil]];

            __weak UIAlertController *weakAlert =
                alert;

            [alert addAction:
                [UIAlertAction
                    actionWithTitle:@"确定"
                    style:UIAlertActionStyleDefault
                    handler:^(UIAlertAction *action) {

                UIAlertController *strongAlert =
                    weakAlert;

                if (strongAlert == nil) {
                    return;
                }

                NSString *text =
                    strongAlert.textFields.firstObject.text;

                NSScanner *scanner =
                    [NSScanner scannerWithString:
                        text ?: @""];

                int value = 0;

                if (![scanner scanInt:&value]) {
                    return;
                }

                if (!scanner.isAtEnd) {
                    return;
                }

                if (value < minimum ||
                    value > maximum) {
                    return;
                }

                currentSlider.value =
                    value;

                [currentSlider
                    sendActionsForControlEvents:
                        UIControlEventValueChanged];
            }]];

            typeof(self) strongSelf =
                weakSelf;

            if (strongSelf != nil) {
                [strongSelf
                    presentViewController:alert
                    animated:YES
                    completion:nil];
            }

        }]
        forControlEvents:UIControlEventTouchUpInside];


        [cell.contentView addSubview:label];
        [cell.contentView addSubview:slider];
        [cell.contentView addSubview:button];


        [NSLayoutConstraint activateConstraints:@[

            [label.leadingAnchor
                constraintEqualToAnchor:
                    cell.contentView.leadingAnchor
                    constant:16],

            [label.trailingAnchor
                constraintEqualToAnchor:
                    cell.contentView.trailingAnchor
                    constant:-16],

            [label.topAnchor
                constraintEqualToAnchor:
                    cell.contentView.topAnchor
                    constant:10],

            [slider.leadingAnchor
                constraintEqualToAnchor:
                    label.leadingAnchor],

            [slider.topAnchor
                constraintEqualToAnchor:
                    label.bottomAnchor
                    constant:5],

            [slider.trailingAnchor
                constraintEqualToAnchor:
                    button.leadingAnchor
                    constant:-10],

            [button.trailingAnchor
                constraintEqualToAnchor:
                    cell.contentView.trailingAnchor
                    constant:-16],

            [button.centerYAnchor
                constraintEqualToAnchor:
                    slider.centerYAnchor],

            [button.widthAnchor
                constraintEqualToConstant:38],

            [button.heightAnchor
                constraintEqualToConstant:38]

        ]];

        return cell;
    }


    UITableViewCell *cell =
        [super tableView:tableView
            cellForRowAtIndexPath:indexPath];

    if ([cell isKindOfClass:
            NSClassFromString(@"PSLinkCell")]) {

        cell.textLabel.textColor =
            UIColor.labelColor;

        cell.accessoryType =
            UITableViewCellAccessoryDisclosureIndicator;
    }

    return cell;
}


- (CGFloat)tableView:(UITableView *)tableView
heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    PSSpecifier *specifier =
        [self specifierAtIndexPath:indexPath];

    NSString *key =
        [specifier propertyForKey:@"key"];

    if ([key isEqualToString:@"keyboardDimOpacity"] ||
        [key isEqualToString:
            @"externalKeyboardHorizontalPercent"] ||
        [key isEqualToString:
            @"internalKeyboardZoomPercent"]) {

        return 82.0;
    }

    return [super tableView:tableView
        heightForRowAtIndexPath:indexPath];
}

@end


#pragma mark - PXRootListController

@interface PXRootListController : PSListController

@end

@implementation PXRootListController

- (NSMutableArray *)specifiers
{
    if (_specifiers == nil) {

        _specifiers =
            [self loadSpecifiersFromPlistName:@"Root"
                                       target:self];
    }

    return _specifiers;
}

@end