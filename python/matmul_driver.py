"""Drive the matmul_axi_lite IP from the PS using the PYNQ overlay API."""
import time
import numpy as np
from pynq import Overlay

A_BASE, B_BASE, CTRL, STATUS, C_BASE = 0x00, 0x40, 0x80, 0x84, 0xC0


class MatMul4x4:
    def __init__(self, bitfile="matmul.bit", ip_name="matmul_axi_lite_0"):
        self.overlay = Overlay(bitfile)          # needs matmul.hwh next to the .bit
        self.ip = getattr(self.overlay, ip_name)

    def multiply(self, A, B, timeout_s=1.0):
        A = np.asarray(A, dtype=np.int16).reshape(16)
        B = np.asarray(B, dtype=np.int16).reshape(16)
        for k in range(16):
            self.ip.write(A_BASE + 4 * k, int(A[k]) & 0xFFFF)
            self.ip.write(B_BASE + 4 * k, int(B[k]) & 0xFFFF)

        self.ip.write(CTRL, 1)
        t0 = time.time()
        while not (self.ip.read(STATUS) & 0x1):
            if time.time() - t0 > timeout_s:
                raise TimeoutError("accelerator did not assert done")

        raw = [self.ip.read(C_BASE + 4 * k) for k in range(16)]
        return np.array(raw, dtype=np.uint32).view(np.int32).reshape(4, 4)


if __name__ == "__main__":
    mm = MatMul4x4()
    rng = np.random.default_rng(0)
    for trial in range(10):
        A = rng.integers(-1000, 1000, (4, 4), dtype=np.int16)
        B = rng.integers(-1000, 1000, (4, 4), dtype=np.int16)
        hw = mm.multiply(A, B)
        sw = A.astype(np.int64) @ B.astype(np.int64)
        assert np.array_equal(hw, sw), f"trial {trial} mismatch\n{hw}\n{sw}"
    print("10/10 random tests match NumPy")
