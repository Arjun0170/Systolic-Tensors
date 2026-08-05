
import numpy as np
import torch
import torch.nn as nn

from mnist import load_mnist


class MLP(nn.Module):
    def __init__(self):
        super().__init__()
        self.fc1 = nn.Linear(784, 64)
        self.fc2 = nn.Linear(64, 10)

    def forward(self, x):
        x = torch.relu(self.fc1(x))
        return self.fc2(x)


def main():
    torch.manual_seed(0)
    x_tr, y_tr, x_te, y_te = load_mnist()
    x_tr = torch.from_numpy(x_tr)
    y_tr = torch.from_numpy(y_tr)
    x_te_t = torch.from_numpy(x_te)
    y_te_t = torch.from_numpy(y_te)

    net = MLP()
    opt = torch.optim.Adam(net.parameters(), lr=1e-3)
    loss_fn = nn.CrossEntropyLoss()

    n, bs, epochs = x_tr.shape[0], 128, 12
    for ep in range(epochs):
        perm = torch.randperm(n)
        net.train()
        for i in range(0, n, bs):
            idx = perm[i:i + bs]
            opt.zero_grad()
            loss = loss_fn(net(x_tr[idx]), y_tr[idx])
            loss.backward()
            opt.step()
        net.eval()
        with torch.no_grad():
            acc = (net(x_te_t).argmax(1) == y_te_t).float().mean().item()
        print(f"epoch {ep + 1}/{epochs}  test_acc={acc * 100:.2f}%")

    # export weights as numpy. Linear stores weight as [out, in]; I transpose
    # to [in, out] so inference is a clean  x @ w.
    sd = net.state_dict()
    np.savez(
        "mlp_weights.npz",
        w1=sd["fc1.weight"].numpy().T.copy(),
        b1=sd["fc1.bias"].numpy(),
        w2=sd["fc2.weight"].numpy().T.copy(),
        b2=sd["fc2.bias"].numpy(),
    )
    print("saved mlp_weights.npz")


if __name__ == "__main__":
    main()
