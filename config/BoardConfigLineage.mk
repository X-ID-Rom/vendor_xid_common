include vendor/xid-common/config/BoardConfigKernel.mk

ifeq ($(BOARD_USES_QCOM_HARDWARE),true)
include vendor/xid-common/config/BoardConfigQcom.mk
endif

include vendor/xid-common/config/BoardConfigSoong.mk
