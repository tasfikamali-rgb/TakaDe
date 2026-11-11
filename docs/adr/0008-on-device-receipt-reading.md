# 8. Read receipts on the device

Status: Accepted (2026-11-11)

Receipts are read with Apple Vision (`VNRecognizeTextRequest`) on the phone, from the
VisionKit document camera or a photo the person picks. The image is not stored or
uploaded. `ReceiptParser` turns recognized lines into a suggestion (shop, total, date,
other amounts) and the person reviews it before it fills the expense form. Nothing is
saved or split automatically. Accuracy on Bengali-script receipts is untested; most
printed receipts in Bangladesh use English for totals.
