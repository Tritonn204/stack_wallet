/* 
 * This file is part of Stack Wallet.
 * 
 * Copyright (c) 2023 Cypher Stack
 * All Rights Reserved.
 * The code is distributed under GPLv3 license, see LICENSE file for details.
 * Generated by Cypher Stack on 2023-05-26
 *
 */

import 'dart:async';

import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:isar/isar.dart';
import 'package:tuple/tuple.dart';

import '../../../../models/isar/models/isar_models.dart';
import '../../../../models/keys/view_only_wallet_data.dart';
import '../../../../notifications/show_flush_bar.dart';
import '../../../../pages/receive_view/generate_receiving_uri_qr_code_view.dart';
import '../../../../providers/db/main_db_provider.dart';
import '../../../../providers/providers.dart';
import '../../../../route_generator.dart';
import '../../../../themes/stack_colors.dart';
import '../../../../utilities/address_utils.dart';
import '../../../../utilities/assets.dart';
import '../../../../utilities/clipboard_interface.dart';
import '../../../../utilities/constants.dart';
import '../../../../utilities/enums/derive_path_type_enum.dart';
import '../../../../utilities/text_styles.dart';
import '../../../../utilities/util.dart';
import '../../../../wallets/crypto_currency/crypto_currency.dart';
import '../../../../wallets/isar/providers/eth/current_token_wallet_provider.dart';
import '../../../../wallets/isar/providers/wallet_info_provider.dart';
import '../../../../wallets/wallet/impl/bitcoin_wallet.dart';
import '../../../../wallets/wallet/intermediate/bip39_hd_wallet.dart';
import '../../../../wallets/wallet/wallet_mixin_interfaces/bcash_interface.dart';
import '../../../../wallets/wallet/wallet_mixin_interfaces/extended_keys_interface.dart';
import '../../../../wallets/wallet/wallet_mixin_interfaces/multi_address_interface.dart';
import '../../../../wallets/wallet/wallet_mixin_interfaces/spark_interface.dart';
import '../../../../wallets/wallet/wallet_mixin_interfaces/view_only_option_interface.dart';
import '../../../../widgets/conditional_parent.dart';
import '../../../../widgets/custom_buttons/app_bar_icon_button.dart';
import '../../../../widgets/custom_loading_overlay.dart';
import '../../../../widgets/desktop/desktop_dialog.dart';
import '../../../../widgets/desktop/secondary_button.dart';
import '../../../../widgets/qr.dart';
import '../../../../widgets/rounded_white_container.dart';

class DesktopReceive extends ConsumerStatefulWidget {
  const DesktopReceive({
    super.key,
    required this.walletId,
    this.contractAddress,
    this.clipboard = const ClipboardWrapper(),
  });

  final String walletId;
  final String? contractAddress;
  final ClipboardInterface clipboard;

  @override
  ConsumerState<DesktopReceive> createState() => _DesktopReceiveState();
}

class _DesktopReceiveState extends ConsumerState<DesktopReceive> {
  late final CryptoCurrency coin;
  late final String walletId;
  late final ClipboardInterface clipboard;
  late final bool supportsSpark;
  late final bool showMultiType;

  int _currentIndex = 0;

  final List<AddressType> _walletAddressTypes = [];
  final Map<AddressType, String> _addressMap = {};
  final Map<AddressType, StreamSubscription<Address?>> _addressSubMap = {};

  Future<void> generateNewAddress() async {
    final wallet = ref.read(pWallets).getWallet(walletId);
    if (wallet is MultiAddressInterface) {
      bool shouldPop = false;
      unawaited(
        showDialog(
          context: context,
          builder: (_) {
            return WillPopScope(
              onWillPop: () async => shouldPop,
              child: Container(
                color: Theme.of(context)
                    .extension<StackColors>()!
                    .overlay
                    .withOpacity(0.5),
                child: const CustomLoadingOverlay(
                  message: "Generating address",
                  eventBus: null,
                ),
              ),
            );
          },
        ),
      );

      final Address? address;
      if (wallet is Bip39HDWallet && wallet is! BCashInterface) {
        DerivePathType? type;
        if (wallet.isViewOnly && wallet is ExtendedKeysInterface) {
          final voData = await wallet.getViewOnlyWalletData()
              as ExtendedKeysViewOnlyWalletData;
          for (final t in wallet.cryptoCurrency.supportedDerivationPathTypes) {
            final testPath = wallet.cryptoCurrency.constructDerivePath(
              derivePathType: t,
              chain: 0,
              index: 0,
            );
            if (testPath.startsWith(voData.xPubs.first.path)) {
              type = t;
              break;
            }
          }
        } else {
          type = DerivePathType.values.firstWhere(
            (e) => e.getAddressType() == _walletAddressTypes[_currentIndex],
          );
        }
        address = await wallet.generateNextReceivingAddress(
          derivePathType: type!,
        );
        final isar = ref.read(mainDBProvider).isar;
        await isar.writeTxn(() async {
          await isar.addresses.put(address!);
        });
        final info = ref.read(pWalletInfo(walletId));
        await info.updateReceivingAddress(
          newAddress: address.value,
          isar: isar,
        );
      } else {
        await wallet.generateNewReceivingAddress();
        address = null;
      }

      shouldPop = true;

      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();

        setState(() {
          _addressMap[_walletAddressTypes[_currentIndex]] =
              address?.value ?? ref.read(pWalletReceivingAddress(walletId));
        });
      }
    }
  }

  Future<void> generateNewSparkAddress() async {
    final wallet = ref.read(pWallets).getWallet(walletId);
    if (wallet is SparkInterface) {
      bool shouldPop = false;
      unawaited(
        showDialog(
          context: context,
          builder: (_) {
            return WillPopScope(
              onWillPop: () async => shouldPop,
              child: Container(
                color: Theme.of(context)
                    .extension<StackColors>()!
                    .overlay
                    .withOpacity(0.5),
                child: const CustomLoadingOverlay(
                  message: "Generating address",
                  eventBus: null,
                ),
              ),
            );
          },
        ),
      );

      final address = await wallet.generateNextSparkAddress();
      await ref.read(mainDBProvider).isar.writeTxn(() async {
        await ref.read(mainDBProvider).isar.addresses.put(address);
      });

      shouldPop = true;

      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        setState(() {
          _addressMap[AddressType.spark] = address.value;
        });
      }
    }
  }

  @override
  void initState() {
    walletId = widget.walletId;
    coin = ref.read(pWalletInfo(walletId)).coin;
    clipboard = widget.clipboard;
    final wallet = ref.read(pWallets).getWallet(walletId);
    supportsSpark = ref.read(pWallets).getWallet(walletId) is SparkInterface;

    if (wallet is ViewOnlyOptionInterface && wallet.isViewOnly) {
      showMultiType = false;
    } else {
      showMultiType = supportsSpark ||
          (wallet is! BCashInterface &&
              wallet is Bip39HDWallet &&
              wallet.supportedAddressTypes.length > 1);
    }

    _walletAddressTypes.add(wallet.info.mainAddressType);

    if (showMultiType) {
      if (supportsSpark) {
        _walletAddressTypes.insert(0, AddressType.spark);
      } else {
        _walletAddressTypes.addAll(
          (wallet as Bip39HDWallet)
              .supportedAddressTypes
              .where((e) => e != wallet.info.mainAddressType),
        );
      }
    }

    if (_walletAddressTypes.length > 1 && wallet is BitcoinWallet) {
      _walletAddressTypes.removeWhere((e) => e == AddressType.p2pkh);
    }

    _addressMap[_walletAddressTypes[_currentIndex]] =
        ref.read(pWalletReceivingAddress(walletId));

    if (showMultiType) {
      for (final type in _walletAddressTypes) {
        _addressSubMap[type] = ref
            .read(mainDBProvider)
            .isar
            .addresses
            .where()
            .walletIdEqualTo(walletId)
            .filter()
            .typeEqualTo(type)
            .sortByDerivationIndexDesc()
            .findFirst()
            .asStream()
            .listen((event) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _addressMap[type] =
                    event?.value ?? _addressMap[type] ?? "[No address yet]";
              });
            }
          });
        });
      }
    }

    super.initState();
  }

  @override
  void dispose() {
    for (final subscription in _addressSubMap.values) {
      subscription.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    debugPrint("BUILD: $runtimeType");

    final String address;
    if (showMultiType) {
      address = _addressMap[_walletAddressTypes[_currentIndex]]!;
    } else {
      address = ref.watch(pWalletReceivingAddress(walletId));
    }

    final wallet =
        ref.watch(pWallets.select((value) => value.getWallet(walletId)));

    final bool canGen;
    if (wallet is ViewOnlyOptionInterface &&
        wallet.isViewOnly &&
        wallet.viewOnlyType == ViewOnlyWalletType.addressOnly) {
      canGen = false;
    } else {
      canGen = (wallet is MultiAddressInterface || supportsSpark);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConditionalParent(
          condition: showMultiType,
          builder: (child) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonHideUnderline(
                child: DropdownButton2<int>(
                  value: _currentIndex,
                  items: [
                    for (int i = 0; i < _walletAddressTypes.length; i++)
                      DropdownMenuItem(
                        value: i,
                        child: Text(
                          supportsSpark &&
                                  _walletAddressTypes[i] == AddressType.p2pkh
                              ? "Transparent address"
                              : "${_walletAddressTypes[i].readableName} address",
                          style: STextStyles.w500_14(context),
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null && value != _currentIndex) {
                      setState(() {
                        _currentIndex = value;
                      });
                    }
                  },
                  isExpanded: true,
                  iconStyleData: IconStyleData(
                    icon: Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: SvgPicture.asset(
                        Assets.svg.chevronDown,
                        width: 12,
                        height: 6,
                        color: Theme.of(context)
                            .extension<StackColors>()!
                            .textFieldActiveSearchIconRight,
                      ),
                    ),
                  ),
                  buttonStyleData: ButtonStyleData(
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .extension<StackColors>()!
                          .textFieldDefaultBG,
                      borderRadius: BorderRadius.circular(
                        Constants.size.circularBorderRadius,
                      ),
                    ),
                  ),
                  dropdownStyleData: DropdownStyleData(
                    offset: const Offset(0, -10),
                    elevation: 0,
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .extension<StackColors>()!
                          .textFieldDefaultBG,
                      borderRadius: BorderRadius.circular(
                        Constants.size.circularBorderRadius,
                      ),
                    ),
                  ),
                  menuItemStyleData: const MenuItemStyleData(
                    padding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                  ),
                ),
              ),
              const SizedBox(
                height: 12,
              ),
              child,
            ],
          ),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () {
                clipboard.setData(
                  ClipboardData(
                    text: address,
                  ),
                );
                showFloatingFlushBar(
                  type: FlushBarType.info,
                  message: "Copied to clipboard",
                  iconAsset: Assets.svg.copy,
                  context: context,
                );
              },
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context)
                        .extension<StackColors>()!
                        .backgroundAppBar,
                    width: 1,
                  ),
                  borderRadius: BorderRadius.circular(
                    Constants.size.circularBorderRadius,
                  ),
                ),
                child: RoundedWhiteContainer(
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Text(
                            "Your ${widget.contractAddress == null ? coin.ticker : ref.watch(
                                pCurrentTokenWallet.select(
                                  (value) => value!.tokenContract.symbol,
                                ),
                              )} address",
                            style: STextStyles.itemSubtitle(context),
                          ),
                          const Spacer(),
                          Row(
                            children: [
                              SvgPicture.asset(
                                Assets.svg.copy,
                                width: 15,
                                height: 15,
                                color: Theme.of(context)
                                    .extension<StackColors>()!
                                    .infoItemIcons,
                              ),
                              const SizedBox(
                                width: 4,
                              ),
                              Text(
                                "Copy",
                                style: STextStyles.link2(context),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(
                        height: 8,
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              address,
                              style: STextStyles.desktopTextExtraExtraSmall(
                                context,
                              ).copyWith(
                                color: Theme.of(context)
                                    .extension<StackColors>()!
                                    .textDark,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),

        if (canGen)
          const SizedBox(
            height: 20,
          ),

        if (canGen)
          SecondaryButton(
            buttonHeight: ButtonHeight.l,
            onPressed: supportsSpark &&
                    _walletAddressTypes[_currentIndex] == AddressType.spark
                ? generateNewSparkAddress
                : generateNewAddress,
            label: "Generate new address",
          ),
        const SizedBox(
          height: 32,
        ),
        Center(
          child: QR(
            data: AddressUtils.buildUriString(
              coin.uriScheme,
              address,
              {},
            ),
            size: 200,
          ),
        ),
        const SizedBox(
          height: 32,
        ),
        // TODO: create transparent button class to account for hover
        GestureDetector(
          onTap: () async {
            if (Util.isDesktop) {
              await showDialog<void>(
                context: context,
                builder: (context) => DesktopDialog(
                  maxHeight: double.infinity,
                  maxWidth: 580,
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const AppBarBackButton(
                            size: 40,
                            iconSize: 24,
                          ),
                          Text(
                            "Generate QR code",
                            style: STextStyles.desktopH3(context),
                          ),
                        ],
                      ),
                      IntrinsicHeight(
                        child: Navigator(
                          onGenerateRoute: RouteGenerator.generateRoute,
                          onGenerateInitialRoutes: (_, __) => [
                            RouteGenerator.generateRoute(
                              RouteSettings(
                                name: GenerateUriQrCodeView.routeName,
                                arguments: Tuple2(coin, address),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            } else {
              unawaited(
                Navigator.of(context).push(
                  RouteGenerator.getRoute(
                    shouldUseMaterialRoute: RouteGenerator.useMaterialPageRoute,
                    builder: (_) => GenerateUriQrCodeView(
                      coin: coin,
                      receivingAddress: address,
                    ),
                    settings: const RouteSettings(
                      name: GenerateUriQrCodeView.routeName,
                    ),
                  ),
                ),
              );
            }
          },
          child: Container(
            color: Colors.transparent,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SvgPicture.asset(
                  Assets.svg.qrcode,
                  width: 14,
                  height: 16,
                  color: Theme.of(context)
                      .extension<StackColors>()!
                      .accentColorBlue,
                ),
                const SizedBox(
                  width: 8,
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    "Create new QR code",
                    style: STextStyles.desktopTextExtraSmall(context).copyWith(
                      color: Theme.of(context)
                          .extension<StackColors>()!
                          .accentColorBlue,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
