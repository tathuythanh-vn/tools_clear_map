public class BinarySearchTree {

    public static class Node {
        int val;
        Node left = null;
        Node right = null;

        Node() {
        }

        Node(int val) {
            this.val = val;
        }

        Node(int val, Node left, Node right) {
            this.val = val;
            this.left = left;
            this.right = right;
        }
    }

    public Node root;

    BinarySearchTree() {
        this.root = null;
    }

    BinarySearchTree(int[] values) {
        if (values.length == 0) {
            return;
        }

        this.root = new Node(values[0]);
        Node currentNode = this.root;

        for (int i = 1; i < values.length; i++) {
            if (values[i] > currentNode.val) {
                currentNode.right = new Node(values[i]);
                currentNode = currentNode.right;
            } else {
                currentNode.left = new Node(values[i]);
                currentNode = currentNode.left;
            }
        }
    }

    public static void printTree(Node root, int space) {
        if (root == null) return;

        space += 5;

        // print right subtree first
        printTree(root.right, space);

        // print current node
        System.out.println();
        for (int i = 5; i < space; i++) {
            System.out.print(" ");
        }
        System.out.println(root.val);

        // print left subtree
        printTree(root.left, space);
    }

    public void bfs(Node root) {
        if (root == null) {
            return;
        }

        bfs(root.left);
        System.out.print(root.val + " - ");
        bfs(root.right);
    }

    static void main() {
        int[] values = {1, 5, 8, 4, 7, 6, 0, 25, 62};
        BinarySearchTree bst = new BinarySearchTree(values);

        printTree(bst.root, 0);
    }
}
