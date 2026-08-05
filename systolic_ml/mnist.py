
import gzip
import struct
import numpy as np


def _read_idx(path):
    with gzip.open(path, "rb") as f:
        magic = struct.unpack(">I", f.read(4))[0]
        ndim = magic & 0xFF
        dims = [struct.unpack(">I", f.read(4))[0] for _ in range(ndim)]
        data = np.frombuffer(f.read(), dtype=np.uint8)
    return data.reshape(dims)


def load_mnist(data_dir="mnist_data"):
    x_tr = _read_idx(f"{data_dir}/train-images-idx3-ubyte.gz")
    y_tr = _read_idx(f"{data_dir}/train-labels-idx1-ubyte.gz")
    x_te = _read_idx(f"{data_dir}/t10k-images-idx3-ubyte.gz")
    y_te = _read_idx(f"{data_dir}/t10k-labels-idx1-ubyte.gz")

    # flatten 28x28 -> 784, scale to [0, 1]
    x_tr = x_tr.reshape(-1, 784).astype(np.float32) / 255.0
    x_te = x_te.reshape(-1, 784).astype(np.float32) / 255.0
    return x_tr, y_tr.astype(np.int64), x_te, y_te.astype(np.int64)
